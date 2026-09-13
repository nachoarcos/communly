import { Link } from "react-router-dom";
import Avatar from "./Avatar";

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
      <div className="post-meta" style={{ display: "flex", alignItems: "center", gap: 6 }}>
        <Avatar src={post.author_avatar_url} size={18} />
        <span>
          por <Link to={`/u/${author}`}>@{author}</Link> · {date}
          {typeof post.like_count === "number" && post.like_count > 0 && (
            <> · {post.like_count} {post.like_count === 1 ? "me gusta" : "me gusta"}</>
          )}
        </span>
      </div>
    </article>
  );
}
