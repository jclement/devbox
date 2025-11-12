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
	ContainerName   string
	Username        string
	PostgresDB      string
	DevServicePort  string
	Hostname        string
	Uptime          string
	Services        []Service
	Snapshots       []Snapshot
	TailscaleStatus *TailscaleStatus
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
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 32px;
        }
        .subtitle {
            color: #666;
            font-size: 16px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .card {
            background: white;
            padding: 25px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        .card h2 {
            color: #333;
            margin-bottom: 20px;
            font-size: 20px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .service {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #eee;
        }
        .service:last-child { border-bottom: none; }
        .service-name {
            font-weight: 600;
            color: #333;
        }
        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }
        .status-running {
            background: #10b981;
            color: white;
        }
        .status-stopped {
            background: #ef4444;
            color: white;
        }
        .service a {
            color: #667eea;
            text-decoration: none;
            font-size: 14px;
        }
        .service a:hover { text-decoration: underline; }
        .snapshot-item {
            padding: 12px;
            background: #f9fafb;
            border-radius: 8px;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .snapshot-info {
            flex: 1;
        }
        .snapshot-name {
            font-weight: 600;
            color: #333;
            margin-bottom: 4px;
        }
        .snapshot-meta {
            font-size: 12px;
            color: #666;
        }
        .snapshot-actions {
            display: flex;
            gap: 8px;
        }
        .btn {
            padding: 6px 14px;
            border: none;
            border-radius: 6px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
        }
        .btn-restore {
            background: #667eea;
            color: white;
        }
        .btn-restore:hover { background: #5568d3; }
        .btn-delete {
            background: #ef4444;
            color: white;
        }
        .btn-delete:hover { background: #dc2626; }
        .btn-create {
            background: #10b981;
            color: white;
            width: 100%;
            padding: 12px;
            font-size: 15px;
        }
        .btn-create:hover { background: #059669; }
        .input-group {
            margin-bottom: 15px;
        }
        .input-group input {
            width: 100%;
            padding: 10px;
            border: 2px solid #e5e7eb;
            border-radius: 6px;
            font-size: 14px;
        }
        .input-group input:focus {
            outline: none;
            border-color: #667eea;
        }
        .empty-state {
            text-align: center;
            padding: 40px 20px;
            color: #666;
        }
        .tailscale-card {
            grid-column: 1 / -1;
            background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%);
            color: white;
        }
        .tailscale-card h2 {
            color: white;
            border-bottom-color: rgba(255,255,255,0.3);
        }
        .tailscale-card .service-name {
            color: white;
        }
        .tailscale-card .service a {
            color: #c7d2fe;
        }
        .funnel-warning {
            background: rgba(255,255,255,0.1);
            padding: 12px;
            border-radius: 6px;
            margin-top: 12px;
            font-size: 13px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 {{.ContainerName}}</h1>
            <p class="subtitle">User: {{.Username}} | Database: {{.PostgresDB}} | Uptime: {{.Uptime}}</p>
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
        const basePath = '/devbox';

        function toggleFunnel(currentlyEnabled) {
            if (!currentlyEnabled) {
                if (!confirm('⚠️ WARNING: This will make your dev service publicly accessible on the internet!\n\nAnyone with the URL can access it.\nOnly your main app (/) will be exposed.\nAdmin tools (/code/, /db/, /mail/, /files/) remain private.\n\nAre you sure?')) {
                    return;
                }
            }

            fetch(basePath + '/api/tailscale/toggle-funnel', { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        alert(data.message);
                        location.reload();
                    } else {
                        alert('Error: ' + data.error);
                    }
                })
                .catch(err => alert('Error: ' + err));
        }

        function createSnapshot() {
            const label = document.getElementById('snapshotLabel').value;
            fetch(basePath + '/api/snapshots/create?label=' + encodeURIComponent(label), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        alert('Snapshot created: ' + data.filename);
                        location.reload();
                    } else {
                        alert('Error: ' + data.error);
                    }
                });
        }

        function restoreSnapshot(filename) {
            if (!confirm('Restore from ' + filename + '? This will drop all current data!')) return;
            fetch(basePath + '/api/snapshots/restore?filename=' + encodeURIComponent(filename), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        alert('Database restored successfully');
                        location.reload();
                    } else {
                        alert('Error: ' + data.error);
                    }
                });
        }

        function deleteSnapshot(filename) {
            if (!confirm('Delete ' + filename + '?')) return;
            fetch(basePath + '/api/snapshots/delete?filename=' + encodeURIComponent(filename), { method: 'POST' })
                .then(r => r.json())
                .then(data => {
                    if (data.success) {
                        location.reload();
                    } else {
                        alert('Error: ' + data.error);
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
	tsAuthKey := os.Getenv("TS_AUTHKEY")
	if tsAuthKey == "" {
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
		ContainerName:   getEnv("CONTAINER_NAME", "devbox"),
		Username:        getEnv("USERNAME", "devbox"),
		PostgresDB:      getEnv("POSTGRES_DB", "devdb"),
		DevServicePort:  getEnv("DEV_SERVICE_PORT", "3000"),
		Hostname:        hostname,
		Uptime:          getUptime(),
		Services:        getServices(),
		Snapshots:       getSnapshots(),
		TailscaleStatus: getTailscaleStatus(),
	}

	cachedStatus = status
	cacheTime = time.Now()

	return status
}

func getTailscaleStatus() *TailscaleStatus {
	tsAuthKey := os.Getenv("TS_AUTHKEY")
	if tsAuthKey == "" {
		return nil
	}

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
	services := []Service{
		{Name: "SSH", Status: checkService(22), URL: ""},
		{Name: "PostgreSQL", Status: checkService(5432), URL: ""},
		{Name: "Caddy", Status: checkService(8443), URL: "/"},
		{Name: "code-server", Status: checkService(8080), URL: "/devbox/code/"},
		{Name: "pgweb", Status: checkService(8081), URL: "/devbox/db/"},
		{Name: "MailHog", Status: checkService(8025), URL: "/devbox/mail/"},
		{Name: "File Browser", Status: checkService(8083), URL: "/devbox/files/"},
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

func getUptime() string {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return "unknown"
	}

	var seconds float64
	fmt.Sscanf(string(data), "%f", &seconds)

	duration := time.Duration(seconds) * time.Second
	days := int(duration.Hours() / 24)
	hours := int(duration.Hours()) % 24
	minutes := int(duration.Minutes()) % 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh %dm", days, hours, minutes)
	} else if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
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

func parseInt(s string) int {
	var i int
	fmt.Sscanf(s, "%d", &i)
	return i
}
