import { Link } from "react-router-dom";

export default function PostCard({ post }) {
  const author = post.author_username || "usuario";
  const date = post.published_at
    ? new Date(post.published_at).toLocaleDateString("es-ES")
    : "";

  return (
    <article className="post-list-item">
      <h2>
        <Link to={`/posts/${post.post_id}`}>{post.title}</Link>
      </h2>
      <div className="post-meta">
        por <Link to={`/u/${author}`}>@{author}</Link> · {date}
      </div>
    </article>
  );
}
