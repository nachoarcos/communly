import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { listModerationQueue, resolveReport } from "../lib/api";

export default function ModerationQueue() {
  const [reports, setReports] = useState([]);
  const [error, setError] = useState(null);
  const [loaded, setLoaded] = useState(false);

  function load() {
    listModerationQueue()
      .then((data) => setReports(data.reports))
      .catch((e) => setError(e.message))
      .finally(() => setLoaded(true));
  }

  useEffect(load, []);

  async function handleResolve(report) {
    try {
      await resolveReport(report.report_id, report.post_id);
      setReports((prev) => prev.filter((r) => r.report_id !== report.report_id));
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <div className="shell">
      <h1 className="section-title">Cola de moderacion</h1>
      {error && <div className="error-banner">{error}</div>}
      {loaded && reports.length === 0 && (
        <p className="empty-state">No hay denuncias abiertas.</p>
      )}
      {reports.map((r) => (
        <div className="comment" key={r.report_id}>
          <p>
            Post <Link to={`/posts/${r.post_id}`}>{r.post_id}</Link>
          </p>
          <p className="post-meta">Motivo: {r.reason || "sin especificar"}</p>
          <button className="btn secondary" onClick={() => handleResolve(r)}>
            Marcar como resuelta
          </button>
        </div>
      ))}
    </div>
  );
}
