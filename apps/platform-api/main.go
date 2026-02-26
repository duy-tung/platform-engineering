package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// Version được set lúc build bằng -ldflags
var Version = "dev"

// ---- Models ----
type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

type HealthResponse struct {
	Status    string `json:"status"`
	Version   string `json:"version"`
	Timestamp string `json:"timestamp"`
}

// ---- Global DB ----
var db *sql.DB

func initDB() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Println("⚠️  DATABASE_URL not set — DB features disabled")
		return
	}

	var err error
	for i := 0; i < 10; i++ {
		db, err = sql.Open("postgres", dsn)
		if err == nil {
			err = db.Ping()
		}
		if err == nil {
			break
		}
		log.Printf("⏳ DB connection attempt %d/10 failed: %v", i+1, err)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		log.Printf("❌ Could not connect to DB after 10 attempts: %v", err)
		return
	}

	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Auto-migrate
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id SERIAL PRIMARY KEY,
			name VARCHAR(100) NOT NULL,
			email VARCHAR(255) UNIQUE NOT NULL,
			created_at TIMESTAMP DEFAULT NOW()
		)
	`)
	if err != nil {
		log.Printf("❌ Migration failed: %v", err)
		return
	}
	log.Println("✅ DB connected + migrated")
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	initDB()

	mux := http.NewServeMux()

	// ---- Health ----
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/ready", handleReady)
	mux.HandleFunc("/version", handleVersion)
	mux.HandleFunc("/db-check", handleDBCheck)

	// ---- CRUD Users ----
	mux.HandleFunc("/users", handleUsers)
	mux.HandleFunc("/users/", handleUserByID)

	// ---- Root ----
	mux.HandleFunc("/", handleRoot)

	log.Printf("🚀 platform-api %s starting on :%s", Version, port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// ---- Handlers ----

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(HealthResponse{
		Status:    "ok",
		Version:   Version,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	})
}

func handleReady(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db != nil {
		if err := db.Ping(); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			json.NewEncoder(w).Encode(map[string]string{"status": "not ready", "error": err.Error()})
			return
		}
	}
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

func handleVersion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	hostname, _ := os.Hostname()
	json.NewEncoder(w).Encode(map[string]string{
		"version":  Version,
		"hostname": hostname,
	})
}

func handleDBCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "error", "message": "DATABASE_URL not configured"})
		return
	}
	start := time.Now()
	err := db.Ping()
	latency := time.Since(start)
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "error", "message": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"message": "database connected",
		"latency": latency.String(),
	})
}

func handleUsers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "database not available"})
		return
	}

	switch r.Method {
	case http.MethodGet:
		listUsers(w)
	case http.MethodPost:
		createUser(w, r)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
	}
}

func handleUserByID(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if db == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"error": "database not available"})
		return
	}

	idStr := strings.TrimPrefix(r.URL.Path, "/users/")
	if idStr == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "missing user id"})
		return
	}

	var user User
	err := db.QueryRow("SELECT id, name, email, created_at FROM users WHERE id = $1", idStr).
		Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err == sql.ErrNoRows {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "user not found"})
		return
	}
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	json.NewEncoder(w).Encode(user)
}

func listUsers(w http.ResponseWriter) {
	rows, err := db.Query("SELECT id, name, email, created_at FROM users ORDER BY id")
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}
	defer rows.Close()

	users := []User{}
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}
	json.NewEncoder(w).Encode(users)
}

func createUser(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "invalid JSON"})
		return
	}
	if input.Name == "" || input.Email == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "name and email required"})
		return
	}

	var user User
	err := db.QueryRow(
		"INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
		input.Name, input.Email,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err != nil {
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(map[string]string{"error": fmt.Sprintf("could not create user: %v", err)})
		return
	}
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"service": "platform-api",
		"version": Version,
		"deploy":  "helm",
		"docs":    "/health, /ready, /version, /db-check, /users",
	})
}
