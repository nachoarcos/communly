const DOMAIN = import.meta.env.VITE_COGNITO_DOMAIN;
const CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID;
const REDIRECT_URI = import.meta.env.VITE_REDIRECT_URI;
const LOGOUT_URI = import.meta.env.VITE_LOGOUT_URI;

const STORAGE_KEY = "communly_tokens";
const VERIFIER_KEY = "communly_pkce_verifier";

// --- PKCE helpers -----------------------------------------------------

function base64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function randomVerifier() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64url(bytes);
}

async function challengeFor(verifier) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier)
  );
  return base64url(digest);
}

// --- Sesion -------------------------------------------------------------

function readTokens() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || "null");
  } catch {
    return null;
  }
}

function writeTokens(tokens) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tokens));
}

function clearTokens() {
  localStorage.removeItem(STORAGE_KEY);
}

// Decodifica el payload del JWT SIN verificar la firma. Es solo para
// decisiones de UI (mostrar/ocultar botones); la validacion real del
// token la hace el JWT Authorizer de API Gateway en cada peticion.
function decodePayload(jwt) {
  try {
    const [, payload] = jwt.split(".");
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json);
  } catch {
    return {};
  }
}

export function getClaims() {
  const tokens = readTokens();
  if (!tokens?.idToken) return null;
  return decodePayload(tokens.idToken);
}

export function isAuthenticated() {
  const tokens = readTokens();
  if (!tokens?.idToken) return false;
  const claims = decodePayload(tokens.idToken);
  return claims.exp && claims.exp * 1000 > Date.now();
}

export function isAdmin() {
  const claims = getClaims();
  const groups = claims?.["cognito:groups"];
  if (!groups) return false;
  return (Array.isArray(groups) ? groups : String(groups).split(",")).includes(
    "admins"
  );
}

// --- Login / logout -------------------------------------------------------

export async function login() {
  const verifier = randomVerifier();
  const challenge = await challengeFor(verifier);
  sessionStorage.setItem(VERIFIER_KEY, verifier);

  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    response_type: "code",
    scope: "openid email profile",
    redirect_uri: REDIRECT_URI,
    code_challenge: challenge,
    code_challenge_method: "S256",
  });

  window.location.href = `${DOMAIN}/oauth2/authorize?${params}`;
}

export function logout() {
  clearTokens();
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    logout_uri: LOGOUT_URI,
  });
  window.location.href = `${DOMAIN}/logout?${params}`;
}

// Se llama desde la pagina /callback con el ?code= que devuelve Cognito.
export async function exchangeCodeForTokens(code) {
  const verifier = sessionStorage.getItem(VERIFIER_KEY);
  sessionStorage.removeItem(VERIFIER_KEY);
  if (!verifier) throw new Error("Falta el code_verifier de la sesion de login");

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CLIENT_ID,
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier,
  });

  const res = await fetch(`${DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) throw new Error("No se pudo intercambiar el codigo por tokens");

  const data = await res.json();
  writeTokens({
    idToken: data.id_token,
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
  });
}

async function refreshTokens() {
  const tokens = readTokens();
  if (!tokens?.refreshToken) return null;

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: CLIENT_ID,
    refresh_token: tokens.refreshToken,
  });

  const res = await fetch(`${DOMAIN}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    clearTokens();
    return null;
  }

  const data = await res.json();
  const updated = { ...tokens, idToken: data.id_token, accessToken: data.access_token };
  writeTokens(updated);
  return updated;
}

// Devuelve un ID token valido, refrescandolo si esta a punto de caducar.
// El JWT Authorizer de API Gateway espera el ID token (lleva el claim
// "aud" = client_id; el access token no lo lleva, ver modules/api-gateway/authorizer.tf).
export async function getValidIdToken() {
  let tokens = readTokens();
  if (!tokens?.idToken) return null;

  const claims = decodePayload(tokens.idToken);
  const expiresInMs = claims.exp * 1000 - Date.now();

  if (expiresInMs < 60_000) {
    tokens = await refreshTokens();
    if (!tokens) return null;
  }

  return tokens.idToken;
}
