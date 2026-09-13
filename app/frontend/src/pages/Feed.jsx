import { useEffect, useState } from "react";
import { listPosts } from "../lib/api";
import PostCard from "../components/PostCard";

export default function Feed() {
  const [posts, setPosts] = useState([]);
  const [cursor, setCursor] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  async function loadPage(nextCursor) {
    setLoading(true);
    setError(null);
    try {
      const data = await listPosts(nextCursor);
      setPosts((prev) => (nextCursor ? [...prev, ...data.items] : data.items));
      setCursor(data.nextCursor);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadPage(null);
  }, []);

  return (
    <div className="shell">
      <h1 className="section-title">Ultimos posts</h1>

      {error && <div className="error-banner">{error}</div>}

      {!loading && posts.length === 0 && (
        <p className="empty-state">
          Todavia no hay nada publicado. Se el primero en escribir algo.
        </p>
      )}

      {posts.map((post) => (
        <PostCard key={post.post_id} post={post} />
      ))}

      {loading && <p className="empty-state">Cargando...</p>}

      {!loading && cursor && (
        <p style={{ marginTop: 24 }}>
          <button className="btn secondary" onClick={() => loadPage(cursor)}>
            Cargar mas
          </button>
        </p>
      )}
    </div>
  );
}
