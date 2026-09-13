import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import { getUserProfile, listUserPosts, toggleFollow } from "../lib/api";
import { isAuthenticated, getClaims } from "../lib/auth";
import PostCard from "../components/PostCard";
import Avatar from "../components/Avatar";

export default function Profile() {
  const { username } = useParams();
  const [profile, setProfile] = useState(null);
  const [posts, setPosts] = useState([]);
  const [following, setFollowing] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    setError(null);
    Promise.all([getUserProfile(username), listUserPosts(username)])
      .then(([profileData, postsData]) => {
        setProfile(profileData);
        setPosts(postsData.posts);
      })
      .catch((e) => setError(e.message));
  }, [username]);

  async function handleFollow() {
    const next = !following;
    setFollowing(next);
    try {
      await toggleFollow(username, next);
    } catch (e) {
      setFollowing(!next);
      setError(e.message);
    }
  }

  if (error) return <div className="shell error-banner">{error}</div>;
  if (!profile) return <div className="shell empty-state">Cargando...</div>;

  const authed = isAuthenticated();
  const claims = getClaims();
  const isOwnProfile = authed && claims?.sub === profile.sub;

  return (
    <div className="shell">
      <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
        <Avatar src={profile.avatarUrl} size={56} />
        <h1 className="post-title" style={{ margin: 0 }}>@{profile.username}</h1>
      </div>
      {profile.bio && <p>{profile.bio}</p>}

      {authed && !isOwnProfile && (
        <button className="btn secondary" onClick={handleFollow} style={{ margin: "12px 0" }}>
          {following ? "Deja de seguir" : "Seguir"}
        </button>
      )}

      <h2 className="section-title" style={{ marginTop: 30 }}>
        Posts
      </h2>
      {posts.length === 0 && <p className="empty-state">Sin posts publicados todavia.</p>}
      {posts.map((post) => (
        <PostCard key={post.post_id} post={post} />
      ))}
    </div>
  );
}
