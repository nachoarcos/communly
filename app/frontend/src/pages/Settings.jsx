import { useEffect, useState } from "react";
import { getOwnProfile, updateOwnProfile, uploadImage } from "../lib/api";

export default function Settings() {
  const [profile, setProfile] = useState(null);
  const [username, setUsername] = useState("");
  const [bio, setBio] = useState("");
  const [avatarUrl, setAvatarUrl] = useState("");
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);

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

  async function handleAvatarSelect(e) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    setUploadingAvatar(true);
    setError(null);
    try {
      const publicPath = await uploadImage(file);
      setAvatarUrl(publicPath);
    } catch (err) {
      setError(err.message);
    } finally {
      setUploadingAvatar(false);
    }
  }

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
        {/* Avatar a la izquierda, con la altura del bloque de usuario
            + bio a la derecha (alignItems: stretch hace que ambas
            columnas midan lo mismo de alto). */}
        <div style={{ display: "flex", gap: 20, alignItems: "stretch", marginBottom: 18 }}>
          <div
            style={{
              width: 110,
              flexShrink: 0,
              borderRadius: 6,
              overflow: "hidden",
              background: "var(--color-surface)",
              border: "1px solid var(--color-border)",
            }}
          >
            {avatarUrl && (
              // eslint-disable-next-line jsx-a11y/alt-text
              <img
                src={avatarUrl}
                style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
              />
            )}
          </div>

          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 14 }}>
            <div className="field" style={{ marginBottom: 0 }}>
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

            <div className="field" style={{ marginBottom: 0, flex: 1 }}>
              <label htmlFor="bio">Bio</label>
              <textarea
                id="bio"
                style={{ minHeight: 70, height: "100%", fontFamily: "inherit" }}
                value={bio}
                onChange={(e) => setBio(e.target.value)}
              />
            </div>
          </div>
        </div>

        <div className="field">
          <label htmlFor="avatar">Cambiar foto de perfil</label>
          <input
            id="avatar"
            type="file"
            accept="image/*"
            onChange={handleAvatarSelect}
            disabled={uploadingAvatar}
          />
          {uploadingAvatar && <p className="post-meta">Subiendo imagen...</p>}
        </div>

        <button className="btn" disabled={busy}>
          Guardar
        </button>
      </form>
    </div>
  );
}
