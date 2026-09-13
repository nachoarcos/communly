import { useEffect, useState } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import {
  getPost,
  listPostComments,
  createComment,
  toggleLike,
  deletePost,
  reportPost,
} from "../lib/api";
import { isAuthenticated, getClaims } from "../lib/auth";
import Markdown from "../components/Markdown";

export default function PostDetail() {
  const { postId } = useParams();
  const navigate = useNavigate();
  const authed = isAuthenticated();
  const claims = getClaims();

  const [post, setPost] = useState(null);
  const [comments, setComments] = useState([]);
  const [liked, setLiked] = useState(false);
  const [commentBody, setCommentBody] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  async function load() {
    try {
      const [postData, commentsData] = await Promise.all([
        getPost(postId),
        listPostComments(postId),
      ]);
      setPost(postData);
      setComments(commentsData.comments);
    } catch (e) {
      setError(e.message);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [postId]);

  async function handleLike() {
    const next = !liked;
    setLiked(next);
    try {
      await toggleLike(postId, next);
    } catch (e) {
      setLiked(!next);
      setError(e.message);
    }
  }

  async function handleComment(e) {
    e.preventDefault();
    if (!commentBody.trim()) return;
    setBusy(true);
    try {
      await createComment(postId, commentBody);
      setCommentBody("");
      const commentsData = await listPostComments(postId);
      setComments(commentsData.comments);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    if (!window.confirm("Borrar este post?")) return;
    try {
      await deletePost(postId);
      navigate("/");
    } catch (e) {
      setError(e.message);
    }
  }

  async function handleReport() {
    const reason = window.prompt("Motivo de la denuncia:");
    if (!reason) return;
    try {
      await reportPost(postId, reason);
      window.alert("Denuncia enviada. Gracias.");
    } catch (e) {
      setError(e.message);
    }
  }

  if (error && !post) return <div className="shell error-banner">{error}</div>;
  if (!post) return <div className="shell empty-state">Cargando...</div>;

  const isAuthor = authed && claims?.sub === post.author_sub;

  return (
    <div className="shell">
      <h1 className="post-title">{post.title}</h1>
      <div className="post-meta">
        por <Link to={`/u/${post.author_username || "usuario"}`}>@{post.author_username || "usuario"}</Link>
        {post.published_at &&
          ` · ${new Date(post.published_at).toLocaleDateString("es-ES")}`}
      </div>

      {error && <div className="error-banner" style={{ marginTop: 16 }}>{error}</div>}

      <div style={{ margin: "20px 0" }}>
        <Markdown source={post.body_markdown} />
      </div>

      <div style={{ display: "flex", gap: 10, marginBottom: 30 }}>
        {authed && (
          <button className={`btn ${liked ? "warm" : "secondary"}`} onClick={handleLike}>
            {liked ? "Ya no me gusta" : "Me gusta"}
          </button>
        )}
        {isAuthor && (
          <>
            <Link className="btn secondary" to={`/posts/${postId}/edit`}>
              Editar
            </Link>
            <button className="btn warm" onClick={handleDelete}>
              Borrar
            </button>
          </>
        )}
        {authed && !isAuthor && (
          <button className="btn secondary" onClick={handleReport}>
            Denunciar
          </button>
        )}
      </div>

      <h2 className="section-title">Comentarios ({comments.length})</h2>

      {authed ? (
        <form onSubmit={handleComment} className="field">
          <textarea
            style={{ minHeight: 90, fontFamily: "inherit" }}
            value={commentBody}
            onChange={(e) => setCommentBody(e.target.value)}
            placeholder="Escribe un comentario"
          />
          <button className="btn" disabled={busy} style={{ marginTop: 10 }}>
            Comentar
          </button>
        </form>
      ) : (
        <p className="empty-state">Inicia sesion para comentar.</p>
      )}

      {comments.map((c) => (
        <div className="comment" key={c.comment_id}>
          <div className="post-meta">
            @{c.author_username || "usuario"} ·{" "}
            {new Date(c.created_at).toLocaleDateString("es-ES")}
          </div>
          <p>{c.body}</p>
        </div>
      ))}
    </div>
  );
}
