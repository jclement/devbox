package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

type StatusData struct {
	ContainerName     string
	Username          string
	PostgresDB        string
	DevServicePort    string
	Hostname          string
	Services          []Service
	Snapshots         []Snapshot
	TailscaleStatus   *TailscaleStatus
	CloudflaredActive bool
}

type Service struct {
	Name   string
	Status string
	URL    string
}

type Snapshot struct {
	Filename string
	Size     string
	Date     string
}

type TailscaleStatus struct {
	Enabled       bool
	TailnetIP     string
	Hostname      string
	FullHostname  string
	FunnelEnabled bool
	PublicURL     string
}

var (
	cachedStatus  *StatusData
	cacheTime     time.Time
	cacheDuration = 10 * time.Second
	snapshotsDir  = "/snapshots"
	db            *sql.DB
)

func invalidateCache() {
	cachedStatus = nil
	cacheTime = time.Time{}
}

func main() {
	// Initialize database connection
	connStr := fmt.Sprintf(
		"host=localhost port=5432 user=%s password=%s dbname=%s sslmode=disable",
		getEnv("POSTGRES_USER", "postgres"),
		getEnv("POSTGRES_PASSWORD", "postgres"),
		getEnv("POSTGRES_DB", "devdb"),
	)

	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Printf("Warning: Could not connect to database: %v", err)
	} else {
		defer db.Close()
	}

	http.HandleFunc("/", handleStatus)
	http.HandleFunc("/api/status", handleAPIStatus)
	http.HandleFunc("/api/snapshots", handleSnapshots)
	http.HandleFunc("/api/snapshots/create", handleCreateSnapshot)
	http.HandleFunc("/api/snapshots/restore", handleRestoreSnapshot)
	http.HandleFunc("/api/snapshots/delete", handleDeleteSnapshot)
	http.HandleFunc("/api/tailscale/toggle-funnel", handleToggleFunnel)

	log.Println("DevBox status server starting on :8082")
	log.Fatal(http.ListenAndServe(":8082", nil))
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	status := getStatus()

	tmpl := `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DevBox - {{.ContainerName}}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600;700&display=swap');

        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'IBM Plex Mono', 'Courier New', monospace;
            background: #000080;
            background-image: repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px);
            min-height: 100vh;
            padding: 20px;
            color: #00ffff;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: #0000aa;
            padding: 20px;
            border: 3px double #00ffff;
            box-shadow: 4px 4px 0 #000040;
            margin-bottom: 20px;
        }
        h1 {
            color: #ffff00;
            margin-bottom: 10px;
            font-size: 28px;
            font-weight: 700;
            text-shadow: 2px 2px 0 #000000;
            letter-spacing: 2px;
        }
        .subtitle {
            color: #00ffff;
            font-size: 13px;
            font-weight: 400;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-top: 20px;
            margin-bottom: 20px;
        }
        .card {
            background: #0000aa;
            padding: 20px;
            border: 3px double #00ffff;
            box-shadow: 4px 4px 0 #000040;
        }
        .card h2 {
            color: #ffff00;
            margin-bottom: 15px;
            font-size: 16px;
            font-weight: 700;
            border-bottom: 2px solid #00ffff;
            padding-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .service {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid #0000ff;
        }
        .service:last-child { border-bottom: none; }
        .service-name {
            font-weight: 600;
            color: #ffffff;
            font-size: 13px;
        }
        .status-badge {
            padding: 2px 10px;
            font-size: 11px;
            font-weight: 700;
            border: 2px solid;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .status-running {
            background: #00aa00;
            color: #00ff00;
            border-color: #00ff00;
        }
        .status-stopped {
            background: #aa0000;
            color: #ff0000;
            border-color: #ff0000;
        }
        .service a {
            color: #00ffff;
            text-decoration: none;
            font-size: 12px;
        }
        .service a:hover {
            text-decoration: underline;
            color: #ffff00;
        }
        .snapshot-item {
            padding: 10px;
            background: #000080;
            border: 1px solid #0000ff;
            margin-bottom: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .snapshot-info {
            flex: 1;
        }
        .snapshot-name {
            font-weight: 600;
            color: #ffff00;
            margin-bottom: 4px;
            font-size: 12px;
        }
        .snapshot-meta {
            font-size: 11px;
            color: #00ffff;
        }
        .snapshot-actions {
            display: flex;
            gap: 6px;
        }
        .btn {
            padding: 6px 12px;
            border: 2px solid;
            font-size: 11px;
            font-weight: 700;
            cursor: pointer;
            transition: all 0.1s;
            font-family: 'IBM Plex Mono', monospace;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .btn:hover {
            transform: translate(2px, 2px);
            box-shadow: none;
        }
        .btn:active {
            transform: translate(4px, 4px);
        }
        .btn-restore {
            background: #0000aa;
            color: #00ffff;
            border-color: #00ffff;
            box-shadow: 2px 2px 0 #000040;
        }
        .btn-delete {
            background: #aa0000;
            color: #ff0000;
            border-color: #ff0000;
            box-shadow: 2px 2px 0 #550000;
        }
        .btn-create {
            background: #00aa00;
            color: #00ff00;
            border-color: #00ff00;
            box-shadow: 2px 2px 0 #005500;
            width: 100%;
            padding: 10px;
            font-size: 13px;
        }
        .input-group {
            margin-bottom: 15px;
        }
        .input-group input {
            width: 100%;
            padding: 8px;
            border: 2px solid #00ffff;
            background: #000080;
            color: #ffff00;
            font-size: 13px;
            font-family: 'IBM Plex Mono', monospace;
        }
        .input-group input:focus {
            outline: none;
            border-color: #ffff00;
            background: #0000aa;
        }
        .input-group input::placeholder {
            color: #0000ff;
        }
        .empty-state {
            text-align: center;
            padding: 30px 20px;
            color: #0000ff;
            font-style: italic;
        }
        .tailscale-card {
            grid-column: 1 / -1;
            background: #aa00aa;
            border-color: #ff00ff;
        }
        .tailscale-card h2 {
            color: #ffff00;
            border-bottom-color: #ff00ff;
        }
        .tailscale-card .service {
            border-bottom-color: #880088;
        }
        .tailscale-card .service-name {
            color: #ffffff;
        }
        .tailscale-card .service a {
            color: #ff00ff;
        }
        .funnel-warning {
            background: #880088;
            padding: 10px;
            border: 2px solid #ff00ff;
            margin-top: 12px;
            font-size: 12px;
            color: #ffff00;
        }
        /* Toast Notification System */
        .toast-container {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 10000;
            display: flex;
            flex-direction: column;
            gap: 10px;
            max-width: 400px;
        }
        .toast {
            background: #0000aa;
            border: 3px double #00ffff;
            box-shadow: 6px 6px 0 #000040;
            padding: 15px 20px;
            color: #ffffff;
            font-size: 13px;
            animation: slideIn 0.3s ease-out;
            position: relative;
            min-width: 300px;
        }
        .toast.success {
            border-color: #00ff00;
        }
        .toast.error {
            border-color: #ff0000;
            background: #aa0000;
        }
        .toast.warning {
            border-color: #ffff00;
        }
        .toast-title {
            font-weight: 700;
            margin-bottom: 5px;
            color: #ffff00;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-size: 12px;
        }
        .toast-message {
            color: #00ffff;
            line-height: 1.4;
        }
        .toast.success .toast-message {
            color: #00ff00;
        }
        .toast.error .toast-message {
            color: #ffffff;
        }
        .toast-close {
            position: absolute;
            top: 5px;
            right: 8px;
            background: none;
            border: none;
            color: #00ffff;
            cursor: pointer;
            font-size: 16px;
            font-weight: 700;
            padding: 0;
            width: 20px;
            height: 20px;
            line-height: 1;
        }
        @keyframes slideIn {
            from {
                transform: translateX(400px);
                opacity: 0;
            }
            to {
                transform: translateX(0);
                opacity: 1;
            }
        }
        @keyframes slideOut {
            from {
                transform: translateX(0);
                opacity: 1;
            }
            to {
                transform: translateX(400px);
                opacity: 0;
            }
        }
        .toast.removing {
            animation: slideOut 0.3s ease-in forwards;
        }
        /* Modal Dialog System */
        .modal-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 128, 0.8);
            z-index: 9999;
            display: none;
            align-items: center;
            justify-content: center;
        }
        .modal-overlay.active {
            display: flex;
        }
        .modal {
            background: #0000aa;
            border: 3px double #ffff00;
            box-shadow: 8px 8px 0 #000040;
            padding: 20px;
            min-width: 400px;
            max-width: 600px;
        }
        .modal-title {
            color: #ffff00;
            font-size: 16px;
            font-weight: 700;
            margin-bottom: 15px;
            border-bottom: 2px solid #ffff00;
            padding-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .modal-message {
            color: #00ffff;
            margin-bottom: 20px;
            line-height: 1.6;
            font-size: 13px;
        }
        .modal-buttons {
            display: flex;
            gap: 10px;
            justify-content: flex-end;
        }
        .modal-btn {
            padding: 8px 20px;
            border: 2px solid;
            font-size: 12px;
            font-weight: 700;
            cursor: pointer;
            font-family: 'IBM Plex Mono', monospace;
            text-transform: uppercase;
            letter-spacing: 1px;
            box-shadow: 2px 2px 0 #000040;
        }
        .modal-btn:hover {
            transform: translate(1px, 1px);
        }
        .modal-btn-yes {
            background: #00aa00;
            color: #00ff00;
            border-color: #00ff00;
        }
        .modal-btn-no {
            background: #aa0000;
            color: #ff0000;
            border-color: #ff0000;
        }
    </style>
</head>
<body>
    <!-- Toast Container -->
    <div class="toast-container" id="toastContainer"></div>

    <!-- Modal Overlay -->
    <div class="modal-overlay" id="modalOverlay">
        <div class="modal">
            <div class="modal-title" id="modalTitle"></div>
            <div class="modal-message" id="modalMessage"></div>
            <div class="modal-buttons">
                <button class="modal-btn modal-btn-yes" id="modalYes">YES</button>
                <button class="modal-btn modal-btn-no" id="modalNo">CANCEL</button>
            </div>
        </div>
    </div>

    <div class="container">
        <div class="header">
            <h1>DEVBOX STATUS &middot; {{.ContainerName}}</h1>
            <p class="subtitle">User: {{.Username}} | Database: {{.PostgresDB}} </p>
        </div>

        {{if .TailscaleStatus}}
        {{if .TailscaleStatus.Enabled}}
        <div class="card tailscale-card">
            <h2>🔒 Tailscale Network</h2>
            <div class="service">
                <div>
                    <div class="service-name">Tailnet Address</div>
                    <div style="font-size: 12px; opacity: 0.9;">{{.TailscaleStatus.TailnetIP}}</div>
                </div>
                <span class="status-badge status-running">connected</span>
            </div>
            <div class="service">
                <div>
                    <div class="service-name">Hostname</div>
                    <div style="font-size: 12px; opacity: 0.9;">{{.TailscaleStatus.FullHostname}}</div>
                </div>
            </div>
            <div class="service">
                <div style="flex: 1;">
                    <div class="service-name">Public Access (Funnel)</div>
                    {{if .TailscaleStatus.FunnelEnabled}}
                        <div style="font-size: 12px; opacity: 0.9;">🌍 Public: <a href="{{.TailscaleStatus.PublicURL}}" target="_blank">{{.TailscaleStatus.PublicURL}}</a></div>
                    {{else}}
                        <div style="font-size: 12px; opacity: 0.9;">🔒 Private (Tailnet only)</div>
                    {{end}}
                </div>
                <button class="btn {{if .TailscaleStatus.FunnelEnabled}}btn-delete{{else}}btn-restore{{end}}" onclick="toggleFunnel({{.TailscaleStatus.FunnelEnabled}})">
                    {{if .TailscaleStatus.FunnelEnabled}}Disable Public{{else}}Enable Public{{end}}
                </button>
            </div>
            {{if .TailscaleStatus.FunnelEnabled}}
            <div class="funnel-warning">
                ⚠️ Your development service is publicly accessible on the internet. Only your main app (/) is exposed; admin tools remain private.
            </div>
            {{end}}
        </div>
        {{end}}
        {{end}}

        {{if .CloudflaredActive}}
        <div class="card">
            <h2>🌐 Cloudflare Tunnel</h2>
            <div class="service">
                <div>
                    <div class="service-name">Tunnel Status</div>
                    <div style="font-size: 12px; opacity: 0.9;">🌍 Active - traffic routed through Cloudflare</div>
                </div>
                <span class="status-badge status-running">active</span>
            </div>
        </div>
        {{end}}

        <div class="grid">
            <div class="card">
                <h2>Services</h2>
                {{range .Services}}
                <div class="service">
                    <div>
                        <div class="service-name">{{.Name}}</div>
                        {{if .URL}}<a href="{{.URL}}" target="_blank">Open →</a>{{end}}
                    </div>
                    <span class="status-badge status-{{.Status}}">{{.Status}}</span>
                </div>
                {{end}}
            </div>

            <div class="card">
                <h2>Database Snapshots</h2>
                <div class="input-group">
                    <input type="text" id="snapshotLabel" placeholder="Snapshot label (optional)">
                </div>
                <button class="btn btn-create" onclick="createSnapshot()">Create Snapshot</button>
                <div style="margin-top: 20px;" id="snapshotList">
                    {{if .Snapshots}}
                        {{range .Snapshots}}
                        <div class="snapshot-item">
                            <div class="snapshot-info">
                                <div class="snapshot-name">{{.Filename}}</div>
                                <div class="snapshot-meta">{{.Size}} • {{.Date}}</div>
                            </div>
                            <div class="snapshot-actions">
                                <button class="btn btn-restore" onclick="restoreSnapshot('{{.Filename}}')">Restore</button>
                                <button class="btn btn-delete" onclick="deleteSnapshot('{{.Filename}}')">Delete</button>
                            </div>
                        </div>
                        {{end}}
                    {{else}}
                        <div class="empty-state">No snapshots yet</div>
                    {{end}}
                </div>
            </div>
        </div>
    </div>

    <script>
        // Use relative URLs since we're served from SERVICE_ROOT
        const basePath = '.';

        // Toast Notification System
        function showToast(title, message, type = 'success') {
            const container = document.getElementById('toastContainer');
            const toast = document.createElement('div');
            toast.className = 'toast ' + type;

            const closeBtn = document.createElement('button');
            closeBtn.className = 'toast-close';
            closeBtn.innerHTML = '&times;';
            closeBtn.onclick = function() { toast.remove(); };

            const titleEl = document.createElement('div');
            titleEl.className = 'toast-title';
            titleEl.textContent = title;

            const messageEl = document.createElement('div');
            messageEl.className = 'toast-message';
            messageEl.textContent = message;

            toast.appendChild(closeBtn);
            toast.appendChild(titleEl);
            toast.appendChild(messageEl);

            container.appendChild(toast);

            // Auto-remove after 5 seconds
            setTimeout(() => {
                toast.classList.add('removing');
                setTimeout(() => toast.remove(), 300);
            }, 5000);
        }

        // Modal Dialog System
        function showConfirm(title, message) {
            return new Promise((resolve) => {
                const overlay = document.getElementById('modalOverlay');
                const titleEl = document.getElementById('modalTitle');
                const messageEl = document.getElementById('modalMessage');
                const yesBtn = document.getElementById('modalYes');
                const noBtn = document.getElementById('modalNo');

                titleEl.textContent = title;
                messageEl.innerHTML = message.replace(/\n/g, '<br>');
                overlay.classList.add('active');

                const handleYes = () => {
                    overlay.classList.remove('active');
                    yesBtn.removeEventListener('click', handleYes);
                    noBtn.removeEventListener('click', handleNo);
                    resolve(true);
                };

                const handleNo = () => {
                    overlay.classList.remove('active');
                    yesBtn.removeEventListener('click', handleYes);
                    noBtn.removeEventListener('click', handleNo);
                    resolve(false);
                };

                yesBtn.addEventListener('click', handleYes);
                noBtn.addEventListener('click', handleNo);

                // Close on overlay click
                overlay.addEventListener('click', (e) => {
                    if (e.target === overlay) {
                        handleNo();
                    }
                });
            });
        }

        async function toggleFunnel(currentlyEnabled) {
            if (!currentlyEnabled) {
                const confirmed = await showConfirm(
                    '⚠️ WARNING: PUBLIC ACCESS',
                    'This will make your dev service publicly accessible on the internet!\n\nAnyone with the URL can access it.\nOnly your main app (/) will be exposed.\nAdmin tools (/code/, /db/, /mail/, /files/) remain private.\n\nAre you sure?'
                );
                if (!confirmed) return;
            }

            fetch(basePath + '/api/tailscale/toggle-funnel', { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        showToast('SUCCESS', data.message, 'success');
                        setTimeout(() => location.reload(), 1500);
                    } else {
                        showToast('ERROR', data.error, 'error');
                    }
                })
                .catch(err => showToast('ERROR', String(err), 'error'));
        }

        function createSnapshot() {
            const label = document.getElementById('snapshotLabel').value;
            fetch(basePath + '/api/snapshots/create?label=' + encodeURIComponent(label), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        showToast('SNAPSHOT CREATED', 'Snapshot saved: ' + data.filename, 'success');
                        setTimeout(() => location.reload(), 1500);
                    } else {
                        showToast('ERROR', data.error, 'error');
                    }
                });
        }

        async function restoreSnapshot(filename) {
            const confirmed = await showConfirm(
                '⚠️ RESTORE DATABASE',
                'Restore from ' + filename + '?\n\nThis will DROP ALL current data!\n\nThis action cannot be undone.'
            );
            if (!confirmed) return;

            fetch(basePath + '/api/snapshots/restore?filename=' + encodeURIComponent(filename), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        showToast('DATABASE RESTORED', 'Successfully restored from snapshot', 'success');
                        setTimeout(() => location.reload(), 1500);
                    } else {
                        showToast('ERROR', data.error, 'error');
                    }
                });
        }

        async function deleteSnapshot(filename) {
            const confirmed = await showConfirm(
                'DELETE SNAPSHOT',
                'Delete ' + filename + '?\n\nThis action cannot be undone.'
            );
            if (!confirmed) return;

            fetch(basePath + '/api/snapshots/delete?filename=' + encodeURIComponent(filename), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        showToast('DELETED', 'Snapshot deleted successfully', 'success');
                        setTimeout(() => location.reload(), 1500);
                    } else {
                        showToast('ERROR', data.error, 'error');
                    }
                });
        }
    </script>
</body>
</html>`

	t := template.Must(template.New("status").Parse(tmpl))
	w.Header().Set("Content-Type", "text/html")
	t.Execute(w, status)
}

func handleAPIStatus(w http.ResponseWriter, r *http.Request) {
	status := getStatus()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func handleSnapshots(w http.ResponseWriter, r *http.Request) {
	snapshots := getSnapshots()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"snapshots": snapshots,
	})
}

func handleCreateSnapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	label := r.URL.Query().Get("label")

	timestamp := time.Now().Format("2006-01-02T1504")
	filename := timestamp
	if label != "" {
		filename = fmt.Sprintf("%s_%s", timestamp, label)
	}
	filename += ".sql"

	snapshotPath := filepath.Join(snapshotsDir, filename)

	cmd := exec.Command("pg_dump",
		"-h", "localhost",
		"-U", getEnv("POSTGRES_USER", "postgres"),
		"-d", getEnv("POSTGRES_DB", "devdb"),
		"-F", "p",
		"-f", snapshotPath,
	)
	cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", getEnv("POSTGRES_PASSWORD", "postgres")))

	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("pg_dump failed: %v, output: %s", err, string(output))
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("%v: %s", err, string(output)),
		})
		return
	}

	// Invalidate cache to show new snapshot immediately
	invalidateCache()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"filename": filename,
	})
}

func handleRestoreSnapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := r.URL.Query().Get("filename")
	if filename == "" {
		http.Error(w, "Missing filename", http.StatusBadRequest)
		return
	}

	snapshotPath := filepath.Join(snapshotsDir, filename)

	// Drop and recreate schemas
	dbName := getEnv("POSTGRES_DB", "devdb")
	dbUser := getEnv("POSTGRES_USER", "postgres")

	if db != nil {
		// Drop all schemas except system ones
		_, _ = db.Exec(`
			DO $$ DECLARE
				r RECORD;
			BEGIN
				FOR r IN (SELECT schema_name FROM information_schema.schemata
						  WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast'))
				LOOP
					EXECUTE 'DROP SCHEMA IF EXISTS ' || quote_ident(r.schema_name) || ' CASCADE';
				END LOOP;
			END $$;
		`)

		// Recreate public schema
		db.Exec("CREATE SCHEMA IF NOT EXISTS public")
		db.Exec(fmt.Sprintf("GRANT ALL ON SCHEMA public TO %s", dbUser))
		db.Exec("GRANT ALL ON SCHEMA public TO public")
	}

	// Restore from snapshot
	cmd := exec.Command("psql",
		"-h", "localhost",
		"-U", dbUser,
		"-d", dbName,
		"-f", snapshotPath,
	)
	cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", getEnv("POSTGRES_PASSWORD", "postgres")))

	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("psql restore failed: %v, output: %s", err, string(output))
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   fmt.Sprintf("%v: %s", err, string(output)),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
	})
}

func handleDeleteSnapshot(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	filename := r.URL.Query().Get("filename")
	if filename == "" {
		http.Error(w, "Missing filename", http.StatusBadRequest)
		return
	}

	snapshotPath := filepath.Join(snapshotsDir, filename)
	if err := os.Remove(snapshotPath); err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	// Invalidate cache to remove deleted snapshot immediately
	invalidateCache()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
	})
}

func handleToggleFunnel(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check if Tailscale is enabled
	checkCmd := exec.Command("tailscale", "status")
	if err := checkCmd.Run(); err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   "Tailscale not enabled on this container",
		})
		return
	}

	// Check current funnel status
	cmd := exec.Command("tailscale", "serve", "status")
	output, _ := cmd.CombinedOutput()
	funnelEnabled := strings.Contains(string(output), "funnel")

	var err error
	var message string

	if funnelEnabled {
		// Disable funnel
		cmd = exec.Command("tailscale", "funnel", "--bg", "--https=443", "off")
		err = cmd.Run()
		message = "Public access disabled. Your services are now only accessible on your Tailnet."
	} else {
		// Enable funnel
		cmd = exec.Command("tailscale", "funnel", "--bg", "--https=443", "on")
		err = cmd.Run()
		hostname := getEnv("TS_HOSTNAME", "devbox")
		message = fmt.Sprintf("Public access enabled! Your service is now available at: https://%s.ts.net", hostname)
	}

	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"success": false,
			"error":   err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": message,
	})
}

func getStatus() *StatusData {
	// Return cached status if fresh enough
	if cachedStatus != nil && time.Since(cacheTime) < cacheDuration {
		return cachedStatus
	}

	hostname, _ := os.Hostname()

	status := &StatusData{
		ContainerName:     getEnv("CONTAINER_NAME", "devbox"),
		Username:          getEnv("USERNAME", "devbox"),
		PostgresDB:        getEnv("POSTGRES_DB", "devdb"),
		DevServicePort:    getEnv("DEV_SERVICE_PORT", "3000"),
		Hostname:          hostname,
		Services:          getServices(),
		Snapshots:         getSnapshots(),
		TailscaleStatus:   getTailscaleStatus(),
		CloudflaredActive: isCloudflaredActive(),
	}

	cachedStatus = status
	cacheTime = time.Now()

	return status
}

func isCloudflaredActive() bool {
	// Check if cloudflared process is running
	cmd := exec.Command("pgrep", "-x", "cloudflared")
	err := cmd.Run()
	return err == nil
}

func getTailscaleStatus() *TailscaleStatus {
	// Get Tailscale status
	cmd := exec.Command("tailscale", "status", "--json")
	output, err := cmd.Output()
	if err != nil {
		return &TailscaleStatus{Enabled: false}
	}

	var statusJSON map[string]interface{}
	if err := json.Unmarshal(output, &statusJSON); err != nil {
		return &TailscaleStatus{Enabled: false}
	}

	// Extract Self info
	self, ok := statusJSON["Self"].(map[string]interface{})
	if !ok {
		return &TailscaleStatus{Enabled: false}
	}

	tailnetIP := ""
	if tailscaleIPs, ok := self["TailscaleIPs"].([]interface{}); ok && len(tailscaleIPs) > 0 {
		tailnetIP = fmt.Sprintf("%v", tailscaleIPs[0])
	}

	hostname := getEnv("TS_HOSTNAME", "devbox")
	suffix := getEnv("TS_SUFFIX", "")
	fullHostname := hostname
	if suffix != "" {
		fullHostname = hostname + "." + suffix
	}

	// Check funnel status
	cmd = exec.Command("tailscale", "serve", "status")
	serveOutput, _ := cmd.CombinedOutput()
	funnelEnabled := strings.Contains(string(serveOutput), "funnel")

	return &TailscaleStatus{
		Enabled:       true,
		TailnetIP:     tailnetIP,
		Hostname:      hostname,
		FullHostname:  fullHostname,
		FunnelEnabled: funnelEnabled,
		PublicURL:     fmt.Sprintf("https://%s", fullHostname),
	}
}

func getServices() []Service {
	serviceRoot := getServiceRoot()
	services := []Service{
		{Name: "SSH", Status: checkService(22), URL: ""},
		{Name: "PostgreSQL", Status: checkService(5432), URL: ""},
		{Name: "Valkey", Status: checkService(6379), URL: ""},
		{Name: "Caddy", Status: checkService(8443), URL: "/"},
		{Name: "code-server", Status: checkService(8080), URL: serviceRoot + "code/"},
		{Name: "pgweb", Status: checkService(8081), URL: serviceRoot + "db/"},
		{Name: "Redis Commander", Status: checkService(8084), URL: serviceRoot + "valkey/"},
		{Name: "MailHog", Status: checkService(8025), URL: serviceRoot + "mail/"},
		{Name: "File Browser", Status: checkService(8083), URL: serviceRoot + "files/"},
	}

	devPort := getEnv("DEV_SERVICE_PORT", "3000")
	if devPort != "3000" && devPort != "" {
		services = append(services, Service{
			Name:   fmt.Sprintf("Dev Service (:%s)", devPort),
			Status: checkService(parseInt(devPort)),
			URL:    "/",
		})
	}

	return services
}

func checkService(port int) string {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("localhost:%d", port), 1*time.Second)
	if err != nil {
		return "stopped"
	}
	conn.Close()
	return "running"
}

func getSnapshots() []Snapshot {
	var snapshots []Snapshot

	files, err := filepath.Glob(filepath.Join(snapshotsDir, "*.sql"))
	if err != nil {
		return snapshots
	}

	// Sort by modification time (newest first)
	sort.Slice(files, func(i, j int) bool {
		iInfo, _ := os.Stat(files[i])
		jInfo, _ := os.Stat(files[j])
		return iInfo.ModTime().After(jInfo.ModTime())
	})

	for _, file := range files {
		info, err := os.Stat(file)
		if err != nil {
			continue
		}

		snapshots = append(snapshots, Snapshot{
			Filename: filepath.Base(file),
			Size:     formatSize(info.Size()),
			Date:     info.ModTime().Format("2006-01-02 15:04"),
		})
	}

	return snapshots
}

func formatSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getServiceRoot() string {
	root := getEnv("SERVICE_ROOT", "/devbox/")
	// Ensure it ends with /
	if !strings.HasSuffix(root, "/") {
		root = root + "/"
	}
	return root
}

func parseInt(s string) int {
	var i int
	fmt.Sscanf(s, "%d", &i)
	return i
}
