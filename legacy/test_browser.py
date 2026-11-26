#!/usr/bin/env python3
# Copyright 2026 The Chromium Legacy Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Run GUI browser smoke checks with a private profile and the sandbox enabled.

Requires Python 3.8+ and websockets 13.1. A portable test kit may place that
unmodified dependency in legacy/_deps. This script never uses a personal profile.
"""

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import platform
import plistlib
import subprocess
import sys
import ssl
import threading
import time
from urllib.parse import urlsplit

DEPENDENCIES = Path(__file__).with_name('_deps')
if DEPENDENCIES.is_dir():
    sys.path.insert(0, str(DEPENDENCIES))
from websockets.sync.client import connect  # noqa: E402

PAYLOAD = b'Chromium Legacy private download fixture\n'


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


class DevTools:
    def __init__(self, url):
        parsed = urlsplit(url)
        if parsed.scheme != 'ws' or parsed.hostname != '127.0.0.1':
            raise ValueError('DevTools must use the private loopback endpoint')
        self.connection = connect(
            url, compression=None, open_timeout=10, close_timeout=1
        )
        self.next_id = 0
        self.events = []

    def command(self, method, parameters=None, session=None, timeout=30):
        self.next_id += 1
        identifier = self.next_id
        message = {
            'id': identifier,
            'method': method,
            'params': parameters or {},
        }
        if session:
            message['sessionId'] = session
        self.connection.send(json.dumps(message))
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(method)
            response = json.loads(self.connection.recv(timeout=remaining))
            if response.get('id') != identifier:
                self.events.append(response)
                continue
            if 'error' in response:
                raise RuntimeError(
                    method + ': ' + json.dumps(response['error'])
                )
            return response.get('result', {})

    def evaluate(self, expression, session):
        result = self.command(
            'Runtime.evaluate',
            {
                'expression': expression,
                'returnByValue': True,
                'awaitPromise': True,
                'timeout': 15000,
            },
            session,
        )
        if 'exceptionDetails' in result:
            raise RuntimeError(json.dumps(result['exceptionDetails']))
        return result['result'].get('value')

    def wait_value(self, expression, session, timeout=30):
        deadline = time.monotonic() + timeout
        last_error = None
        while time.monotonic() < deadline:
            try:
                value = self.evaluate(expression, session)
                if value:
                    return value
            except RuntimeError as error:
                last_error = str(error)
            time.sleep(0.1)
        raise TimeoutError(expression + ': ' + str(last_error))

    def navigate(self, url, session):
        result = self.command('Page.navigate', {'url': url}, session)
        if result.get('errorText'):
            raise RuntimeError(json.dumps(result))
        self.wait_value(
            'document.readyState === "complete" && location.href === '
            + json.dumps(url),
            session,
        )


def handler(html):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/download':
                data, content_type = PAYLOAD, 'text/plain'
            elif self.path == '/fixture':
                data, content_type = html, 'text/html; charset=utf-8'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            if self.path == '/download':
                self.send_header(
                    'Content-Disposition',
                    'attachment; filename="chromium-legacy-smoke.txt"',
                )
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *_):
            pass

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--application', required=True, type=Path)
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--process-probe', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--startup-timeout', type=int, default=45)
    args = parser.parse_args()
    if args.startup_timeout <= 0:
        parser.error('--startup-timeout must be positive')
    application = args.application.resolve(strict=True)
    process_probe = args.process_probe.resolve(strict=True)
    info = plistlib.loads((application / 'Contents/Info.plist').read_bytes())
    executable = application / 'Contents/MacOS' / info['CFBundleExecutable']
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    profile = directory / 'profile'
    downloads = directory / 'downloads'
    downloads.mkdir()
    html = (
        Path(__file__)
        .with_name('tests')
        .joinpath('browser_smoke.html')
        .read_bytes()
    )
    servers = []
    browser = None
    client = None
    report = {
        'application': str(application),
        'host_macos': platform.mac_ver()[0],
        'host_architecture': platform.machine(),
        'expected_version': args.expected_version,
        'scope': 'GUI browser with private profile; no sandbox, certificate, GPU or origin-check bypass flags.',
        'checks': [],
    }

    def check(name, passed, detail=None):
        report['checks'].append(
            {'name': name, 'passed': bool(passed), 'detail': detail}
        )
        print(name + ': ' + ('PASS' if passed else 'FAIL'), flush=True)
        if not passed:
            raise RuntimeError(name + ': ' + str(detail))

    log = (directory / 'browser.log').open('wb')
    try:
        signature = subprocess.run(
            [
                '/usr/bin/codesign',
                '--verify',
                '--deep',
                '--strict',
                str(application),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        check('bundle signatures', signature.returncode == 0, signature.stderr)
        bundle_files = [executable]
        for framework in (application / 'Contents/Frameworks').glob(
            '*.framework'
        ):
            candidate = (
                framework
                / 'Versions'
                / info['CFBundleShortVersionString']
                / framework.stem
            )
            if candidate.is_file():
                bundle_files.append(candidate)
        report['bundle_sha256'] = {}
        for path in bundle_files:
            report['bundle_sha256'][str(path.relative_to(application))] = (
                file_sha256(path)
            )
        http = ThreadingHTTPServer(('127.0.0.1', 0), handler(html))
        servers.append(http)
        http.daemon_threads = True
        threading.Thread(target=http.serve_forever, daemon=True).start()
        config = directory / 'certificate.cnf'
        config.write_text(
            '[req]\ndistinguished_name=dn\nx509_extensions=extensions\nprompt=no\n[dn]\nCN=localhost\n[extensions]\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n'
        )
        subprocess.run(
            [
                '/usr/bin/openssl',
                'req',
                '-x509',
                '-sha256',
                '-newkey',
                'rsa:2048',
                '-nodes',
                '-days',
                '2',
                '-config',
                str(config),
                '-keyout',
                str(directory / 'key.pem'),
                '-out',
                str(directory / 'certificate.pem'),
            ],
            check=True,
            stdout=log,
            stderr=log,
            timeout=30,
        )
        tls = ThreadingHTTPServer(('127.0.0.1', 0), handler(html))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(
            str(directory / 'certificate.pem'), str(directory / 'key.pem')
        )
        tls.socket = context.wrap_socket(tls.socket, server_side=True)
        servers.append(tls)
        tls.daemon_threads = True
        threading.Thread(target=tls.serve_forever, daemon=True).start()
        command = [
            str(executable),
            '--user-data-dir=' + str(profile),
            '--remote-debugging-port=0',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-default-apps',
            '--enable-logging=stderr',
            'about:blank',
        ]
        report['command'] = command
        browser = subprocess.Popen(command, stdout=log, stderr=log)
        report['browser_pid'] = browser.pid
        deadline = time.monotonic() + args.startup_timeout
        active_port = profile / 'DevToolsActivePort'
        while not active_port.exists() and time.monotonic() < deadline:
            if browser.poll() is not None:
                raise RuntimeError(
                    'Browser exited before DevTools: ' + str(browser.returncode)
                )
            time.sleep(0.1)
        check(
            'startup',
            active_port.is_file(),
            {
                'timeout_seconds': args.startup_timeout,
                'browser_alive': browser.poll() is None,
            },
        )
        endpoint = active_port.read_text().splitlines()
        port = int(endpoint[0])
        check(
            'private DevTools endpoint',
            0 < port < 65536 and endpoint[1].startswith('/devtools/browser/'),
        )
        client = DevTools('ws://127.0.0.1:' + str(port) + endpoint[1])
        version = client.command('Browser.getVersion')
        report['version'] = version
        check(
            'browser version',
            version['product'].rsplit('/', 1)[-1] == args.expected_version,
            version,
        )
        target = client.command('Target.createTarget', {'url': 'about:blank'})[
            'targetId'
        ]
        session = client.command(
            'Target.attachToTarget', {'targetId': target, 'flatten': True}
        )['sessionId']
        client.command('Page.enable', session=session)
        fixture_url = 'http://127.0.0.1:' + str(http.server_port) + '/fixture'
        client.navigate(fixture_url, session)
        web_results = client.wait_value('window.smokeResults', session)
        report['web_checks'] = web_results
        report['gpu'] = client.command('SystemInfo.getInfo')
        processes = client.command('SystemInfo.getProcessInfo')['processInfo']
        report['devtools_processes'] = processes
        # Short-lived notification/audio helpers may exit between the CDP
        # snapshot and inspection. Inspect the actual security-critical browser,
        # renderer, GPU and network processes; retain the full snapshot above.
        required_types = {
            'browser',
            'renderer',
            'GPU',
            'network.mojom.NetworkService',
        }
        process_ids = sorted(
            {int(p['id']) for p in processes if p['type'] in required_types}
            | {browser.pid}
        )
        probe = subprocess.run(
            [str(process_probe), *map(str, process_ids)],
            capture_output=True,
            text=True,
            timeout=15,
        )
        report['process_probe'] = {
            'returncode': probe.returncode,
            'stderr': probe.stderr,
        }
        check('process inspection', probe.returncode == 0, probe.stderr)
        states = json.loads(probe.stdout)
        report['process_states'] = states
        state_by_pid = {p['pid']: p for p in states}
        runtime_roots = {application}
        for state in states:
            runtime_binary = Path(state['path']).resolve(strict=True)
            try:
                runtime_binary.relative_to(application)
                continue
            except ValueError:
                pass
            # App Translocation and macOS code_sign_clone may execute an exact
            # OS-owned copy. Bind that copy to the selected sealed app rather
            # than bypassing Gatekeeper or trusting a matching basename.
            candidates = [
                parent
                for parent in runtime_binary.parents
                if parent.name
                in (application.name, application.name + '.bundle')
            ]
            check('runtime bundle location', bool(candidates), state)
            runtime_root = candidates[0]
            relative = runtime_binary.relative_to(runtime_root)
            selected_binary = application / relative
            check(
                'runtime executable bytes',
                selected_binary.is_file()
                and file_sha256(runtime_binary) == file_sha256(selected_binary),
                str(relative),
            )
            if runtime_root not in runtime_roots:
                runtime_info = plistlib.loads(
                    (runtime_root / 'Contents/Info.plist').read_bytes()
                )
                keys = (
                    'CFBundleIdentifier',
                    'CFBundleShortVersionString',
                    'CFBundleExecutable',
                )
                check(
                    'runtime bundle identity',
                    all(runtime_info.get(key) == info.get(key) for key in keys),
                )
                seal = Path('Contents/_CodeSignature/CodeResources')
                check(
                    'runtime resource seal',
                    (runtime_root / seal).read_bytes()
                    == (application / seal).read_bytes(),
                )
                runtime_signature = subprocess.run(
                    [
                        '/usr/bin/codesign',
                        '--verify',
                        '--deep',
                        '--strict',
                        str(runtime_root),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                check(
                    'runtime bundle signatures',
                    runtime_signature.returncode == 0,
                    runtime_signature.stderr,
                )
                runtime_roots.add(runtime_root)
        report['runtime_application_roots'] = sorted(map(str, runtime_roots))
        check(
            'visible browser window',
            state_by_pid[browser.pid]['onscreen_windows'] > 0,
            state_by_pid[browser.pid],
        )
        renderer_ids = [
            p['id'] for p in processes if p['type'].lower() == 'renderer'
        ]
        check('renderer present', bool(renderer_ids))
        for pid in renderer_ids:
            check(
                'renderer sandbox ' + str(pid),
                state_by_pid[pid]['sandbox_status'] == 1,
            )
        gpu_ids = [p['id'] for p in processes if p['type'].lower() == 'gpu']
        check('GPU process present', bool(gpu_ids))
        for pid in gpu_ids:
            check(
                'GPU sandbox ' + str(pid),
                state_by_pid[pid]['sandbox_status'] == 1,
            )
        network_ids = [
            p['id']
            for p in processes
            if p['type'] == 'network.mojom.NetworkService'
        ]
        check('network process present', bool(network_ids))
        for pid in network_ids:
            check(
                'network sandbox ' + str(pid),
                state_by_pid[pid]['sandbox_status'] == 1,
            )
        ax = client.command('Accessibility.getFullAXTree', session=session)
        check(
            'renderer accessibility tree',
            any(
                n.get('role', {}).get('value') == 'RootWebArea'
                for n in ax['nodes']
            ),
        )
        client.navigate('https://example.com/', session)
        check(
            'trusted HTTPS navigation',
            client.evaluate('document.title', session) == 'Example Domain',
        )
        invalid_tls = client.command(
            'Page.navigate',
            {'url': 'https://127.0.0.1:' + str(tls.server_port) + '/fixture'},
            session,
        )
        check(
            'untrusted TLS rejected',
            invalid_tls.get('errorText') == 'net::ERR_CERT_AUTHORITY_INVALID',
            invalid_tls,
        )
        client.navigate(fixture_url, session)
        client.command(
            'Browser.setDownloadBehavior',
            {
                'behavior': 'allow',
                'downloadPath': str(downloads),
                'eventsEnabled': True,
            },
        )
        client.command(
            'Page.navigate',
            {'url': 'http://127.0.0.1:' + str(http.server_port) + '/download'},
            session,
        )
        downloaded = downloads / 'chromium-legacy-smoke.txt'
        deadline = time.monotonic() + 20
        while (
            not downloaded.is_file() or downloaded.read_bytes() != PAYLOAD
        ) and time.monotonic() < deadline:
            time.sleep(0.1)
        check(
            'download bytes',
            downloaded.is_file() and downloaded.read_bytes() == PAYLOAD,
        )
        report['download_sha256'] = hashlib.sha256(
            downloaded.read_bytes()
        ).hexdigest()
        # Report all independent browsing/security checks even if one Web API
        # failed. A failed feature still fails the complete run.
        for result in web_results:
            check(result['name'], result['passed'], result.get('error'))
        report['passed'] = True
    except Exception as error:
        report['passed'] = False
        report['error'] = str(error)
        print('Browser check failed: ' + str(error), flush=True)
    finally:
        if client:
            try:
                client.command('Browser.close', timeout=5)
            except Exception:
                pass
            client.connection.close()
        if browser:
            for action, timeout in [(None, 5), ('terminate', 3), ('kill', 1)]:
                if browser.poll() is not None:
                    break
                if action:
                    getattr(browser, action)()
                try:
                    browser.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    pass
            report['browser_returncode'] = browser.poll()
            if browser.poll() is None:
                report['passed'] = False
                report['cleanup_error'] = (
                    'Owned browser did not exit after bounded shutdown attempts'
                )
        for server in servers:
            server.shutdown()
            server.server_close()
        log.close()
        (directory / 'report.json').write_text(
            json.dumps(report, indent=2) + '\n'
        )
    return not report.get('passed', False)


if __name__ == '__main__':
    raise SystemExit(main())
