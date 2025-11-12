#!/usr/bin/env python3
import os
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
import socket

class StatusHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress logging

    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(self.generate_html().encode())
        elif self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(self.get_status()).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def get_status(self):
        # Get supervisor status
        try:
            result = subprocess.run(['supervisorctl', 'status'],
                                    capture_output=True, text=True, timeout=5)
            services = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    parts = line.split()
                    if len(parts) >= 2:
                        services.append({
                            'name': parts[0],
                            'status': parts[1],
                            'running': parts[1] == 'RUNNING'
                        })
        except:
            services = []

        # Get PostgreSQL status
        try:
            result = subprocess.run(['psql', '-h', 'localhost', '-U', 'postgres', '-d',
                                     os.environ.get('POSTGRES_DB', 'devdb'), '-c',
                                     'SELECT version();', '-t'],
                                    capture_output=True, text=True, timeout=5)
            pg_version = result.stdout.strip().split('\n')[0].strip() if result.returncode == 0 else 'Unavailable'
        except:
            pg_version = 'Unavailable'

        # Get uptime
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
                uptime_str = f"{int(uptime_seconds // 3600)}h {int((uptime_seconds % 3600) // 60)}m"
        except:
            uptime_str = "Unknown"

        # Get memory info
        try:
            result = subprocess.run(['free', '-h'], capture_output=True, text=True, timeout=5)
            mem_lines = result.stdout.strip().split('\n')
            mem_info = mem_lines[1].split() if len(mem_lines) > 1 else []
            memory = f"{mem_info[2]}/{mem_info[1]}" if len(mem_info) > 2 else "Unknown"
        except:
            memory = "Unknown"

        return {
            'container_name': os.environ.get('CONTAINER_NAME', 'devbox'),
            'hostname': socket.gethostname(),
            'username': os.environ.get('USERNAME', 'developer'),
            'database': os.environ.get('POSTGRES_DB', 'devdb'),
            'workspace': '/workspace',
            'uptime': uptime_str,
            'memory': memory,
            'pg_version': pg_version,
            'services': services,
            'dev_port': os.environ.get('DEV_SERVICE_PORT', '3000'),
        }

    def generate_html(self):
        status = self.get_status()
        services_html = '\n'.join([
            f'''
            <div class="service-item {'running' if s['running'] else 'stopped'}">
                <span class="status-dot"></span>
                <span class="service-name">{s['name']}</span>
                <span class="service-status">{s['status']}</span>
            </div>
            ''' for s in status['services']
        ])

        return f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevBox Status</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 2rem;
        }}
        .container {{
            max-width: 1000px;
            margin: 0 auto;
        }}
        .header {{
            background: white;
            border-radius: 12px;
            padding: 2rem;
            margin-bottom: 1.5rem;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #667eea;
            font-size: 2rem;
            margin-bottom: 0.5rem;
        }}
        .subtitle {{
            color: #666;
            font-size: 1rem;
        }}
        .grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1.5rem;
            margin-bottom: 1.5rem;
        }}
        .card {{
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        .card h2 {{
            color: #667eea;
            font-size: 1.2rem;
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid #f0f0f0;
        }}
        .info-row {{
            display: flex;
            justify-content: space-between;
            padding: 0.5rem 0;
            border-bottom: 1px solid #f5f5f5;
        }}
        .info-label {{
            color: #666;
            font-weight: 500;
        }}
        .info-value {{
            color: #333;
            font-family: monospace;
        }}
        .service-item {{
            display: flex;
            align-items: center;
            padding: 0.75rem;
            margin: 0.5rem 0;
            background: #f8f9fa;
            border-radius: 8px;
            gap: 0.75rem;
        }}
        .status-dot {{
            width: 12px;
            height: 12px;
            border-radius: 50%;
            flex-shrink: 0;
        }}
        .service-item.running .status-dot {{
            background: #10b981;
            box-shadow: 0 0 8px rgba(16, 185, 129, 0.5);
        }}
        .service-item.stopped .status-dot {{
            background: #ef4444;
        }}
        .service-name {{
            font-weight: 600;
            color: #333;
            flex: 1;
        }}
        .service-status {{
            color: #666;
            font-size: 0.875rem;
            font-family: monospace;
        }}
        .links {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
        }}
        .link-button {{
            display: block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            padding: 1rem;
            border-radius: 8px;
            text-align: center;
            font-weight: 600;
            transition: transform 0.2s, box-shadow 0.2s;
        }}
        .link-button:hover {{
            transform: translateY(-2px);
            box-shadow: 0 6px 12px rgba(0,0,0,0.2);
        }}
        .link-icon {{
            font-size: 1.5rem;
            display: block;
            margin-bottom: 0.5rem;
        }}
        .footer {{
            text-align: center;
            color: white;
            margin-top: 2rem;
            opacity: 0.9;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 DevBox Control Panel</h1>
            <p class="subtitle">Development Environment Status & Quick Links</p>
        </div>

        <div class="card" style="margin-bottom: 1.5rem;">
            <h2>🔗 Quick Links</h2>
            <div class="links">
                <a href="/devbox/code/" class="link-button">
                    <span class="link-icon">💻</span>
                    VS Code
                </a>
                <a href="/devbox/db/" class="link-button">
                    <span class="link-icon">🗄️</span>
                    Database Admin
                </a>
                <a href="/devbox/mail/" class="link-button">
                    <span class="link-icon">📧</span>
                    Mail Tester
                </a>
                <a href="/" class="link-button">
                    <span class="link-icon">🌐</span>
                    Your App :{status['dev_port']}
                </a>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>📊 Container Info</h2>
                <div class="info-row">
                    <span class="info-label">Container:</span>
                    <span class="info-value">{status['container_name']}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Hostname:</span>
                    <span class="info-value">{status['hostname']}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">User:</span>
                    <span class="info-value">{status['username']}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Uptime:</span>
                    <span class="info-value">{status['uptime']}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Memory:</span>
                    <span class="info-value">{status['memory']}</span>
                </div>
            </div>

            <div class="card">
                <h2>🗄️ Database Info</h2>
                <div class="info-row">
                    <span class="info-label">Database:</span>
                    <span class="info-value">{status['database']}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Version:</span>
                    <span class="info-value" style="font-size: 0.75rem;">{status['pg_version'][:50]}...</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Host:</span>
                    <span class="info-value">localhost:5432</span>
                </div>
                <div class="info-row">
                    <span class="info-label">User:</span>
                    <span class="info-value">postgres</span>
                </div>
            </div>
        </div>

        <div class="card" style="margin-bottom: 1.5rem;">
            <h2>⚙️ Services Status</h2>
            {services_html}
        </div>

        <div class="footer">
            <p>DevBox • Ephemeral Development Environment</p>
        </div>
    </div>

    <script>
        // Auto-refresh every 10 seconds
        setTimeout(() => location.reload(), 10000);
    </script>
</body>
</html>'''

if __name__ == '__main__':
    port = int(os.environ.get('STATUS_PORT', 8082))
    server = HTTPServer(('127.0.0.1', port), StatusHandler)
    print(f'DevBox Status Server running on port {port}')
    server.serve_forever()
