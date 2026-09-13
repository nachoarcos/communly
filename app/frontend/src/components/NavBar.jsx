import { Link, useNavigate } from "react-router-dom";
import { login, logout, isAuthenticated, isAdmin, getClaims } from "../lib/auth";

export default function NavBar() {
  const navigate = useNavigate();
  const authed = isAuthenticated();
  const claims = getClaims();

  return (
    <header className="navbar">
      <div className="navbar-inner">
        <Link to="/" className="wordmark">
          Communly
        </Link>
        <nav className="nav-links">
          {authed ? (
            <>
              <Link to="/new">Escribir</Link>
              <Link to="/me/feed">Mi feed</Link>
              <Link to="/me/notifications">Notificaciones</Link>
              {isAdmin() && <Link to="/admin/moderation">Moderacion</Link>}
              <Link to="/settings">{claims?.email ? "Ajustes" : "Perfil"}</Link>
              <button onClick={logout}>Salir</button>
            </>
          ) : (
            <button onClick={() => login()}>Entrar</button>
          )}
        </nav>
      </div>
    </header>
  );
}
