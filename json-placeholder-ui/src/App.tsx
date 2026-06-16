import { useEffect, useState } from "react"

type User = {
  id: number
  name: string
  email: string
  phone: string
  website: string
  address: {
    street: string
    suite: string
    city: string
    zipCode: string | null
    geo: { lat: string; lng: string }
  }
  company: {
    name: string
    catchPhrase: string
    bs: string
  }
}

const API_BASE = import.meta.env.VITE_API_BASE_URL

const AVATAR_COLORS = [
  ["#7c3aed", "#4c1d95"],
  ["#0891b2", "#164e63"],
  ["#059669", "#064e3b"],
  ["#d97706", "#451a03"],
  ["#dc2626", "#450a0a"],
  ["#7c3aed", "#3b0764"],
  ["#0284c7", "#0c4a6e"],
  ["#16a34a", "#052e16"],
  ["#9333ea", "#3b0764"],
  ["#ea580c", "#431407"],
]

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map(w => w[0].toUpperCase())
    .join("")
}

function UserCard({ user, index }: { user: User; index: number }) {
  const [flipped, setFlipped] = useState(false)
  const [fg, bg] = AVATAR_COLORS[index % AVATAR_COLORS.length]

  return (
    <div
      className={`card-scene${flipped ? " is-flipped" : ""}`}
      onClick={() => setFlipped(f => !f)}
      role="button"
      aria-label={`${flipped ? "Hide" : "Show"} details for ${user.name}`}
    >
      <div className="card-flipper">

        {/* ── Front ── */}
        <div className="card-face card-front">
          <div className="user-card-header">
            <div className="avatar" style={{ background: `linear-gradient(135deg, ${fg} 0%, ${bg} 100%)` }}>
              {initials(user.name)}
            </div>
            <div className="user-id">#{user.id}</div>
          </div>
          <div className="user-card-body">
            <h2 className="user-name">{user.name}</h2>
            <ul className="user-details">
              <li className="detail-row">
                <span className="detail-icon">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <path d="M2 4l6 5 6-5M2 4h12v8H2z" strokeLinejoin="round" />
                  </svg>
                </span>
                <a className="detail-link" href={`mailto:${user.email}`} onClick={e => e.stopPropagation()}>{user.email}</a>
              </li>
              <li className="detail-row">
                <span className="detail-icon">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <path d="M3 2h3l1.5 4-2 1.5a10 10 0 004 4L11 9.5l4 1.5v3a1 1 0 01-1 1A13 13 0 012 3a1 1 0 011-1z" strokeLinejoin="round" />
                  </svg>
                </span>
                <span className="detail-text">{user.phone}</span>
              </li>
              <li className="detail-row">
                <span className="detail-icon">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <circle cx="8" cy="8" r="6" />
                    <path d="M2 8h12M8 2c-2 2-3 4-3 6s1 4 3 6M8 2c2 2 3 4 3 6s-1 4-3 6" strokeLinejoin="round" />
                  </svg>
                </span>
                <a className="detail-link" href={`https://${user.website}`} target="_blank" rel="noreferrer" onClick={e => e.stopPropagation()}>
                  {user.website}
                </a>
              </li>
            </ul>
            <div className="flip-hint">Click to see more</div>
          </div>
        </div>

        {/* ── Back ── */}
        <div className="card-face card-back">
          <div className="back-section">
            <div className="back-section-title">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M8 1C5.24 1 3 3.24 3 6c0 3.75 5 9 5 9s5-5.25 5-9c0-2.76-2.24-5-5-5zm0 6.75a1.75 1.75 0 110-3.5 1.75 1.75 0 010 3.5z" strokeLinejoin="round" />
              </svg>
              Address
            </div>
            <div className="back-rows">
              <div className="back-row">
                <span className="back-label">Street</span>
                <span className="back-value">{user.address.street}, {user.address.suite}</span>
              </div>
              <div className="back-row">
                <span className="back-label">City</span>
                <span className="back-value">{user.address.city}</span>
              </div>
              {user.address.zipCode && (
                <div className="back-row">
                  <span className="back-label">Zip</span>
                  <span className="back-value">{user.address.zipCode}</span>
                </div>
              )}
              <div className="back-row">
                <span className="back-label">Geo</span>
                <span className="back-value">{user.address.geo.lat}, {user.address.geo.lng}</span>
              </div>
            </div>
          </div>

          <div className="back-divider" />

          <div className="back-section">
            <div className="back-section-title">
              <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="1" y="4" width="14" height="10" rx="1.5" />
                <path d="M5 4V3a3 3 0 016 0v1" strokeLinejoin="round" />
              </svg>
              Company
            </div>
            <div className="back-rows">
              <div className="back-row">
                <span className="back-label">Name</span>
                <span className="back-value">{user.company.name}</span>
              </div>
              <div className="back-row">
                <span className="back-label">Phrase</span>
                <span className="back-value">{user.company.catchPhrase}</span>
              </div>
              <div className="back-row">
                <span className="back-label">BS</span>
                <span className="back-value">{user.company.bs}</span>
              </div>
            </div>
          </div>

          <div className="flip-hint">Click to go back</div>
        </div>

      </div>
    </div>
  )
}

export default function App() {
  const [users, setUsers] = useState<User[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState("")

  useEffect(() => {
    fetch(`${API_BASE}/json-placeholder/users`)
      .then(res => {
        if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
        return res.json() as Promise<User[]>
      })
      .then(data => { setUsers(data); setLoading(false) })
      .catch(err => { setError(String(err)); setLoading(false) })
  }, [])

  const filtered = users.filter(u =>
    u.name.toLowerCase().includes(search.toLowerCase()) ||
    u.email.toLowerCase().includes(search.toLowerCase()) ||
    u.website.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-left">
          <h1>Users</h1>
          {!loading && !error && (
            <span className="user-count">{filtered.length} of {users.length}</span>
          )}
        </div>
        <input
          className="search-input"
          type="text"
          placeholder="Search by name, email, or website…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          disabled={loading || !!error}
        />
      </header>

      {loading && (
        <div className="loading">
          <div className="spinner" /> Fetching users…
        </div>
      )}

      {!loading && error && (
        <div className="error-box">
          <strong>Failed to load users</strong>
          <span>{error}</span>
          <code>{API_BASE}/json-placeholder/users</code>
        </div>
      )}

      {!loading && !error && filtered.length === 0 && (
        <div className="empty-state">No users match your search.</div>
      )}

      {!loading && !error && filtered.length > 0 && (
        <div className="user-grid">
          {filtered.map((user) => (
            <UserCard key={user.id} user={user} index={users.indexOf(user)} />
          ))}
        </div>
      )}
    </div>
  )
}
