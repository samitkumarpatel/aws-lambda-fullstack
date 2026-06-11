import { useState } from "react"
import { Form, useLoaderData, useNavigation } from "react-router"

type SuccessResult = {
  data: Record<string, unknown>
  status: number
  ok: boolean
  url: string
}
type ErrorResult = { error: string; url: string }
type LoaderResult = SuccessResult | ErrorResult | null

export async function loader({ request }: { request: Request }): Promise<LoaderResult> {
  const urlParam = new URL(request.url).searchParams.get("url")
  if (!urlParam) return null
  try {
    const res = await fetch(urlParam)
    const data = await res.json()
    return { data, status: res.status, ok: res.ok, url: urlParam }
  } catch (e) {
    return { error: String(e), url: urlParam }
  }
}

// ── Pill colour by header name prefix ──────────────
function pillClass(name: string) {
  if (name.startsWith("sec-"))     return "header-pill pill-sec"
  if (name.startsWith("x-"))       return "header-pill pill-x"
  if (name.startsWith("accept"))   return "header-pill pill-accept"
  if (name.startsWith("content"))  return "header-pill pill-content"
  if (name.startsWith("cache"))    return "header-pill pill-cache"
  return "header-pill pill-default"
}

type ViewMode = "pill" | "card"

// ── View toggle ─────────────────────────────────────
function ViewToggle({ mode, onChange }: { mode: ViewMode; onChange: (m: ViewMode) => void }) {
  return (
    <div className="view-toggle">
      <button className={`toggle-btn ${mode === "pill" ? "active" : ""}`} onClick={() => onChange("pill")}>
        Pill
      </button>
      <button className={`toggle-btn ${mode === "card" ? "active" : ""}`} onClick={() => onChange("card")}>
        Card
      </button>
    </div>
  )
}

// ── Headers card with live filter + view switch ─────
function HeadersCard({ headers }: { headers: Record<string, unknown> }) {
  const [search, setSearch] = useState("")
  const [view, setView] = useState<ViewMode>("pill")
  const entries = Object.entries(headers).filter(([k]) =>
    k.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="card">
      <div className="card-top">
        <span className="card-key">headers</span>
        <span className="card-count">{Object.keys(headers).length}</span>
        <input
          className="header-search"
          placeholder="filter headers…"
          value={search}
          onChange={e => setSearch(e.target.value)}
        />
        <ViewToggle mode={view} onChange={setView} />
      </div>
      <div className="card-body">
        {entries.length === 0 && <span className="empty">no match</span>}

        {view === "pill" && entries.length > 0 && (
          <div className="headers-list">
            {entries.map(([k, v]) => (
              <div key={k} className="header-row">
                <span className={pillClass(k)}>{k}</span>
                <span className="header-val">{String(v)}</span>
              </div>
            ))}
          </div>
        )}

        {view === "card" && entries.length > 0 && (
          <div className="headers-grid">
            {entries.map(([k, v]) => (
              <div key={k} className="header-card">
                <div className={`header-card-key ${pillClass(k).replace("header-pill ", "")}`}>{k}</div>
                <div className="header-card-val">{String(v)}</div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

// ── Primitive value display ─────────────────────────
function PrimitiveCard({ label, value }: { label: string; value: unknown }) {
  let cls = "primitive-value pv-str"
  if (typeof value === "number")  cls = "primitive-value pv-num"
  if (typeof value === "boolean") cls = "primitive-value pv-bool"
  if (value === null)             cls = "primitive-value pv-null"

  return (
    <div className="card">
      <div className="card-top">
        <span className="card-key">{label}</span>
      </div>
      <div className="card-body">
        <span className={cls}>{JSON.stringify(value)}</span>
      </div>
    </div>
  )
}

// ── Generic object card ─────────────────────────────
function ObjectCard({ label, value }: { label: string; value: Record<string, unknown> }) {
  return (
    <div className="card">
      <div className="card-top">
        <span className="card-key">{label}</span>
        <span className="card-count">{Object.keys(value).length}</span>
      </div>
      <div className="card-body">
        <div className="object-rows">
          {Object.entries(value).map(([k, v]) => (
            <div key={k} className="object-row">
              <span className="obj-key">{k}</span>
              <span className="obj-val">{JSON.stringify(v)}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

// ── Route each field to the right card ─────────────
function FieldCard({ label, value }: { label: string; value: unknown }) {
  if (label === "headers" && typeof value === "object" && value !== null && !Array.isArray(value))
    return <HeadersCard headers={value as Record<string, unknown>} />

  if (typeof value === "object" && value !== null && !Array.isArray(value))
    return <ObjectCard label={label} value={value as Record<string, unknown>} />

  return <PrimitiveCard label={label} value={value} />
}

// ── Full response view ──────────────────────────────
function ResponseView({ result }: { result: SuccessResult }) {
  const { data, status, ok, url } = result
  const message = typeof data.message === "string" ? data.message : null
  const rest = Object.entries(data).filter(([k]) => k !== "message")

  return (
    <>
      <div className="status-bar">
        <span className={`badge ${ok ? "badge-ok" : "badge-err"}`}>{status} {ok ? "OK" : "Error"}</span>
        <span className="badge badge-method">GET</span>
        <span className="status-url">{url}</span>
      </div>

      <div className="cards">
        {message !== null && (
          <div className="card card-message">
            <div className="card-top">
              <span className="card-key">message</span>
            </div>
            <div className="card-body">
              <div className="message-value">{message}</div>
            </div>
          </div>
        )}

        {rest.map(([k, v]) => (
          <FieldCard key={k} label={k} value={v} />
        ))}
      </div>
    </>
  )
}

// ── Page ────────────────────────────────────────────
export default function Home() {
  const result = useLoaderData<LoaderResult>()
  const navigation = useNavigation()
  const loading = navigation.state === "loading"

  return (
    <div className="app">
      <div className="app-header">
        <h1>API Explorer</h1>
        <p>Enter any URL to inspect the JSON response</p>
      </div>

      <Form method="get" className="url-form">
        <input
          key={result?.url ?? ""}
          name="url"
          type="text"
          defaultValue={result?.url ?? ""}
          placeholder="https://api.your-task.dev/nothing/ping"
          className="url-input"
          autoComplete="off"
          spellCheck={false}
        />
        <button type="submit" disabled={loading} className="send-btn">
          {loading ? "Sending…" : "Send"}
        </button>
      </Form>

      {loading && (
        <div className="loading">
          <div className="spinner" /> Fetching…
        </div>
      )}

      {!loading && result && "error" in result && (
        <div className="error-box">{result.error}</div>
      )}

      {!loading && result && "data" in result && (
        <ResponseView result={result} />
      )}
    </div>
  )
}
