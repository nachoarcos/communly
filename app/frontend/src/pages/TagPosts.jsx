import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { listPostsByTag } from "../lib/api";
import PostCard from "../components/PostCard";

export default function TagPosts() {
  const { tag } = useParams();
  const [posts, setPosts] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    listPostsByTag(tag)
      .then((data) => setPosts(data.posts))
      .catch((e) => setError(e.message));
  }, [tag]);

  return (
    <div className="shell">
      <h1 className="section-title">
        Posts con <span className="tag-pill">{tag}</span>
      </h1>
      {error && <div className="error-banner">{error}</div>}
      {posts.length === 0 && !error && (
        <p className="empty-state">Nadie ha publicado con este tag todavia.</p>
      )}
      {posts.map((post) => (
        <PostCard key={post.post_id} post={post} />
      ))}
    </div>
  );
}
