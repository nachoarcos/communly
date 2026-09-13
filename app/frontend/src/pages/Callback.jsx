import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { exchangeCodeForTokens } from "../lib/auth";
import { getOwnProfile } from "../lib/api";

export default function Callback() {
  const navigate = useNavigate();
  const [error, setError] = useState(null);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const code = params.get("code");
    const oauthError = params.get("error_description") || params.get("error");

    if (oauthError) {
      setError(oauthError);
      return;
    }
    if (!code) {
      setError("Falta el parametro code en la URL de retorno");
      return;
    }

    exchangeCodeForTokens(code)
      .then(() => getOwnProfile())
      .then((profile) => {
        // Si el registro degrado sin username (colision de ultima hora,
        // ver post_confirmation trigger), se manda directo a elegir uno.
        navigate(profile.needs_username ? "/settings" : "/", { replace: true });
      })
      .catch((e) => setError(e.message));
  }, [navigate]);

  return (
    <div className="shell">
      {error ? (
        <div className="error-banner">{error}</div>
      ) : (
        <p className="empty-state">Completando el inicio de sesion...</p>
      )}
    </div>
  );
}
