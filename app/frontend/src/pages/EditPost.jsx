import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { getPost, updatePost } from "../lib/api";

export default function EditPost() {
  const { postId } = useParams();
  const navigate = useNavigate();
  const [title, setTitle] = useState("");
  const [bodyMarkdown, setBodyMarkdown] = useState("");
  const [status, setStatus] = useState("draft");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    getPost(postId)
      .then((post) => {
        setTitle(post.title);
        setBodyMarkdown(post.body_markdown);
        setStatus(post.status);
        setLoaded(true);
      })
      .catch((e) => setError(e.message));
  }, [postId]);

  async function handleSubmit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await updatePost(postId, { title, bodyMarkdown, status });
      navigate(`/posts/${postId}`);
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  if (!loaded && !error) return <div className="shell empty-state">Cargando...</div>;

  return (
    <div className="shell">
      <h1 className="section-title">Editar post</h1>

      {error && <div className="error-banner">{error}</div>}

      <form onSubmit={handleSubmit}>
        <div className="field">
          <label htmlFor="title">Titulo</label>
          <input id="title" value={title} onChange={(e) => setTitle(e.target.value)} required />
        </div>

        <div className="field">
          <label htmlFor="body">Contenido (markdown)</label>
          <textarea
            id="body"
            value={bodyMarkdown}
            onChange={(e) => setBodyMarkdown(e.target.value)}
            required
          />
        </div>

        <div className="field">
          <label htmlFor="status">Estado</label>
          <select id="status" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="published">Publicado</option>
            <option value="draft">Borrador</option>
          </select>
        </div>

        <button className="btn" disabled={busy}>
          Guardar cambios
        </button>
      </form>
    </div>
  );
}
