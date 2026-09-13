import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { getPost, updatePost, uploadImage } from "../lib/api";

export default function EditPost() {
  const { postId } = useParams();
  const navigate = useNavigate();
  const [title, setTitle] = useState("");
  const [bodyMarkdown, setBodyMarkdown] = useState("");
  const [tagsInput, setTagsInput] = useState("");
  const [status, setStatus] = useState("draft");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    getPost(postId)
      .then((post) => {
        setTitle(post.title);
        setBodyMarkdown(post.body_markdown);
        setTagsInput((post.tags || []).join(", "));
        setStatus(post.status);
        setLoaded(true);
      })
      .catch((e) => setError(e.message));
  }, [postId]);

  async function handleImageSelect(e) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    setUploading(true);
    setError(null);
    try {
      const publicPath = await uploadImage(file);
      setBodyMarkdown((prev) => `${prev}\n\n![imagen](${publicPath})\n`);
    } catch (err) {
      setError(err.message);
    } finally {
      setUploading(false);
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const tags = tagsInput
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean);
      await updatePost(postId, { title, bodyMarkdown, status, tags });
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
          <label htmlFor="image">Insertar imagen</label>
          <input
            id="image"
            type="file"
            accept="image/*"
            onChange={handleImageSelect}
            disabled={uploading}
          />
          {uploading && <p className="post-meta">Subiendo imagen...</p>}
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
          <label htmlFor="tags">Tags (separados por comas)</label>
          <input
            id="tags"
            value={tagsInput}
            onChange={(e) => setTagsInput(e.target.value)}
            placeholder="react, aws, tutoriales"
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
