import { useEffect, useState } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import {
  getPost,
  listPostComments,
  createComment,
  toggleLike,
  deletePost,
  reportPost,
  uploadImage,
} from "../lib/api";
import { isAuthenticated, getClaims } from "../lib/auth";
import Markdown from "../components/Markdown";
import Avatar from "../components/Avatar";

export default function PostDetail() {
  const { postId } = useParams();
  const navigate = useNavigate();
  const authed = isAuthenticated();
  const claims = getClaims();

  const [post, setPost] = useState(null);
  const [comments, setComments] = useState([]);
  const [liked, setLiked] = useState(false);
  const [likeCount, setLikeCount] = useState(0);
  const [commentBody, setCommentBody] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [uploadingComment, setUploadingComment] = useState(false);

  async function load() {
    try {
      const [postData, commentsData] = await Promise.all([
        getPost(postId),
        listPostComments(postId),
      ]);
      setPost(postData);
      setLikeCount(postData.like_count || 0);
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
    setLikeCount((c) => Math.max(0, c + (next ? 1 : -1)));
    try {
      await toggleLike(postId, next);
    } catch (e) {
      setLiked(!next);
      setLikeCount((c) => Math.max(0, c + (next ? -1 : 1)));
      setError(e.message);
    }
  }

  async function handleCommentImageSelect(e) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    setUploadingComment(true);
    setError(null);
    try {
      const publicPath = await uploadImage(file);
      setCommentBody((prev) => `${prev}\n\n![imagen](${publicPath})\n`);
    } catch (err) {
      setError(err.message);
    } finally {
      setUploadingComment(false);
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
      <div className="post-meta" style={{ display: "flex", alignItems: "center", gap: 8 }}>
        <Avatar src={post.author_avatar_url} size={24} />
        <span>
          por <Link to={`/u/${post.author_username || "usuario"}`}>@{post.author_username || "usuario"}</Link>
          {post.published_at &&
            ` · ${new Date(post.published_at).toLocaleDateString("es-ES")}`}
        </span>
      </div>

      {error && <div className="error-banner" style={{ marginTop: 16 }}>{error}</div>}

      <div style={{ margin: "20px 0" }}>
        <Markdown source={post.body_markdown} />
      </div>

      {post.tags && post.tags.length > 0 && (
        <div style={{ marginBottom: 20, display: "flex", gap: 8, flexWrap: "wrap" }}>
          {post.tags.map((tag) => (
            <Link key={tag} to={`/tags/${encodeURIComponent(tag)}`} className="tag-pill">
              {tag}
            </Link>
          ))}
        </div>
      )}

      <div style={{ display: "flex", gap: 10, marginBottom: 30, alignItems: "center" }}>
        <span className="post-meta">
          {likeCount} {likeCount === 1 ? "me gusta" : "me gusta"}
        </span>
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
          <div style={{ marginTop: 8 }}>
            <input
              type="file"
              accept="image/*"
              onChange={handleCommentImageSelect}
              disabled={uploadingComment}
            />
            {uploadingComment && <span className="post-meta"> Subiendo imagen...</span>}
          </div>
          <button className="btn" disabled={busy} style={{ marginTop: 10 }}>
            Comentar
          </button>
        </form>
      ) : (
        <p className="empty-state">Inicia sesion para comentar.</p>
      )}

      {comments.map((c) => (
        <div className="comment" key={c.comment_id}>
          <div className="post-meta" style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <Avatar src={c.author_avatar_url} size={20} />
            <span>
              @{c.author_username || "usuario"} ·{" "}
              {new Date(c.created_at).toLocaleDateString("es-ES")}
            </span>
          </div>
          <Markdown source={c.body} />
        </div>
      ))}
    </div>
  );
}
