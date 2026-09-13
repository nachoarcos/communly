import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { createPost, uploadImage } from "../lib/api";

export default function NewPost() {
  const navigate = useNavigate();
  const [title, setTitle] = useState("");
  const [bodyMarkdown, setBodyMarkdown] = useState("");
  const [tagsInput, setTagsInput] = useState("");
  const [status, setStatus] = useState("published");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [uploading, setUploading] = useState(false);

  async function handleImageSelect(e) {
    const file = e.target.files?.[0];
    e.target.value = ""; // permite volver a elegir el mismo fichero despues
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
      const post = await createPost({ title, bodyMarkdown, status, tags });
      navigate(`/posts/${post.post_id}`);
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  return (
    <div className="shell">
      <h1 className="section-title">Escribir un post</h1>

      {error && <div className="error-banner">{error}</div>}

      <form onSubmit={handleSubmit}>
        <div className="field">
          <label htmlFor="title">Titulo</label>
          <input
            id="title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
          />
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
            <option value="published">Publicado (visible en el feed)</option>
            <option value="draft">Borrador (solo tu lo ves)</option>
          </select>
        </div>

        <button className="btn" disabled={busy}>
          {status === "published" ? "Publicar" : "Guardar borrador"}
        </button>
      </form>
    </div>
  );
}
