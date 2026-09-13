import { useEffect, useState } from "react";
import { getOwnProfile, updateOwnProfile } from "../lib/api";

export default function Settings() {
  const [profile, setProfile] = useState(null);
  const [username, setUsername] = useState("");
  const [bio, setBio] = useState("");
  const [avatarUrl, setAvatarUrl] = useState("");
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    getOwnProfile()
      .then((data) => {
        setProfile(data);
        setUsername(data.username || "");
        setBio(data.bio || "");
        setAvatarUrl(data.avatar_url || "");
      })
      .catch((e) => setError(e.message));
  }, []);

  async function handleSubmit(e) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      const updated = await updateOwnProfile({ username, bio, avatarUrl });
      setProfile(updated);
      setSaved(true);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  }

  if (!profile && !error) return <div className="shell empty-state">Cargando...</div>;

  return (
    <div className="shell">
      <h1 className="section-title">Ajustes de perfil</h1>

      {profile?.needs_username && (
        <div className="error-banner">
          Tu cuenta se creo sin nombre de usuario (alguien lo reservo justo antes que tu).
          Elige uno para poder publicar y que te puedan encontrar.
        </div>
      )}
      {error && <div className="error-banner">{error}</div>}
      {saved && !error && <p style={{ color: "#2f6f3e" }}>Perfil actualizado.</p>}

      <form onSubmit={handleSubmit}>
        <div className="field">
          <label htmlFor="username">Nombre de usuario</label>
          <input
            id="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            pattern="[a-z0-9_]{3,30}"
            title="3-30 caracteres: minusculas, numeros y guion bajo"
            required
          />
        </div>

        <div className="field">
          <label htmlFor="bio">Bio</label>
          <textarea
            id="bio"
            style={{ minHeight: 90, fontFamily: "inherit" }}
            value={bio}
            onChange={(e) => setBio(e.target.value)}
          />
        </div>

        <div className="field">
          <label htmlFor="avatar">URL del avatar</label>
          <input id="avatar" value={avatarUrl} onChange={(e) => setAvatarUrl(e.target.value)} />
        </div>

        <button className="btn" disabled={busy}>
          Guardar
        </button>
      </form>
    </div>
  );
}
