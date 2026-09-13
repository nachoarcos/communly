resource "aws_cloudfront_function" "spa_routing" {
  name    = "${local.name_prefix}-spa-routing"
  runtime = "cloudfront-js-1.0"
  comment = "Reescribe rutas de cliente (React Router) a /index.html; S3 no tiene un objeto real para /callback, /posts/123, etc."
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Si la ruta ya apunta a un fichero real (tiene extension, p.ej.
      // /assets/index-abc123.js o /favicon.ico), se deja pasar tal cual.
      if (uri.includes('.')) {
        return request;
      }

      // Cualquier otra ruta (/callback, /posts/123, /settings, /u/alguien...)
      // es una ruta de React Router, no un objeto real en S3 -- se
      // reescribe a index.html para que la SPA la resuelva del lado
      // del cliente (React Router lee la URL real del navegador via
      // window.location, no se pierde informacion al reescribir aqui
      // solo el objeto que se sirve).
      request.uri = '/index.html';
      return request;
    }
  EOT
}
