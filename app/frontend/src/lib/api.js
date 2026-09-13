import { getValidIdToken } from "./auth";

// replace(/\/+$/, "") quita cualquier barra final: si VITE_API_BASE_URL
// viniera con "/" al final (p.ej. el invoke_url del stage $default de
// una HTTP API SIEMPRE la lleva), concatenar con rutas que tambien
// empiezan por "/" produciria "...//ruta", que no coincide con ninguna
// ruta real de API Gateway y se manifiesta como un fallo de CORS
// confuso en vez de un 404 claro.
const BASE_URL = (import.meta.env.VITE_API_BASE_URL || "").replace(/\/+$/, "");

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export async function apiFetch(path, { method = "GET", body, auth = false } = {}) {
  const headers = { "Content-Type": "application/json" };

  if (auth) {
    const idToken = await getValidIdToken();
    if (!idToken) throw new ApiError(401, "No autenticado");
    headers.Authorization = `Bearer ${idToken}`;
  }

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    throw new ApiError(res.status, data.error || `Error ${res.status}`);
  }
  return data;
}

// --- Posts ---------------------------------------------------------------

export const listPosts = (cursor) =>
  apiFetch(`/posts${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ""}`);

export const getPost = (postId) => apiFetch(`/posts/${postId}`);

export const listPostComments = (postId) => apiFetch(`/posts/${postId}/comments`);

export const listPostsByTag = (tag) => apiFetch(`/tags/${encodeURIComponent(tag)}/posts`);

export const createPost = (payload) =>
  apiFetch("/posts", { method: "POST", body: payload, auth: true });

export const updatePost = (postId, payload) =>
  apiFetch(`/posts/${postId}`, { method: "PUT", body: payload, auth: true });

export const deletePost = (postId) =>
  apiFetch(`/posts/${postId}`, { method: "DELETE", auth: true });

export const createComment = (postId, body) =>
  apiFetch(`/posts/${postId}/comments`, { method: "POST", body: { body }, auth: true });

export const toggleLike = (postId, liked) =>
  apiFetch(`/posts/${postId}/likes`, { method: liked ? "PUT" : "DELETE", auth: true });

export const reportPost = (postId, reason) =>
  apiFetch(`/posts/${postId}/reports`, { method: "POST", body: { reason }, auth: true });

export const requestImageUpload = (contentType) =>
  apiFetch("/me/images", {
    method: "POST",
    body: { contentType },
    auth: true,
  });

// Pide la URL prefirmada y sube el fichero directamente a S3 (esa
// segunda petición NO pasa por la API, va directa al bucket con la URL
// firmada). Devuelve la ruta publica lista para insertar en markdown.
export async function uploadImage(file) {
  const { uploadUrl, publicPath } = await requestImageUpload(file.type);

  const res = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": file.type },
    body: file,
  });
  if (!res.ok) {
    throw new ApiError(res.status, "No se pudo subir la imagen");
  }

  return publicPath;
}

// --- Usuarios / perfil -----------------------------------------------------

export const getUserProfile = (username) => apiFetch(`/users/${username}`);

export const listUserPosts = (username) => apiFetch(`/users/${username}/posts`);

export const listOwnPosts = () => apiFetch("/me/posts", { auth: true });

export const toggleFollow = (username, following) =>
  apiFetch(`/users/${username}/follow`, { method: following ? "PUT" : "DELETE", auth: true });

export const getOwnProfile = () => apiFetch("/me/profile", { auth: true });

export const updateOwnProfile = (payload) =>
  apiFetch("/me/profile", { method: "PUT", body: payload, auth: true });

export const listOwnFeed = () => apiFetch("/me/feed", { auth: true });

export const listOwnNotifications = () => apiFetch("/me/notifications", { auth: true });

// --- Moderacion (admin) -----------------------------------------------------

export const listModerationQueue = () => apiFetch("/admin/moderation", { auth: true });

export const resolveReport = (reportId, postId) =>
  apiFetch(`/admin/reports/${reportId}/resolve`, {
    method: "POST",
    body: { postId },
    auth: true,
  });
