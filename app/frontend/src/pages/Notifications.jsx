import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { listOwnNotifications } from "../lib/api";

export default function Notifications() {
  const [items, setItems] = useState([]);
  const [error, setError] = useState(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    listOwnNotifications()
      .then((data) => setItems(data.notifications))
      .catch((e) => setError(e.message))
      .finally(() => setLoaded(true));
  }, []);

  return (
    <div className="shell">
      <h1 className="section-title">Notificaciones</h1>
      {error && <div className="error-banner">{error}</div>}
      {loaded && items.length === 0 && (
        <p className="empty-state">Sin notificaciones por ahora.</p>
      )}
      {items.map((n, i) => (
        <div className="comment" key={i}>
          <p>
            {n.type === "new_comment" ? "Nuevo comentario en tu post " : "Notificacion en "}
            <Link to={`/posts/${n.post_id}`}>{n.post_id}</Link>
          </p>
        </div>
      ))}
    </div>
  );
}
