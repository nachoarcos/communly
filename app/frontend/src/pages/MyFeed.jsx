import { useEffect, useState } from "react";
import { listOwnFeed } from "../lib/api";
import { Link } from "react-router-dom";

export default function MyFeed() {
  const [items, setItems] = useState([]);
  const [error, setError] = useState(null);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    listOwnFeed()
      .then((data) => setItems(data.feed))
      .catch((e) => setError(e.message))
      .finally(() => setLoaded(true));
  }, []);

  return (
    <div className="shell">
      <h1 className="section-title">Mi feed</h1>
      {error && <div className="error-banner">{error}</div>}
      {loaded && items.length === 0 && (
        <p className="empty-state">
          Nada por aqui todavia. Sigue a algun autor para ver sus posts en tu feed.
        </p>
      )}
      {items.map((item) => (
        <article className="post-list-item" key={`${item.post_id}-${item.published_at}`}>
          <h2>
            <Link to={`/posts/${item.post_id}`}>{item.post_title || item.post_id}</Link>
          </h2>
          <div className="post-meta">
            {new Date(item.published_at).toLocaleDateString("es-ES")}
          </div>
        </article>
      ))}
    </div>
  );
}
