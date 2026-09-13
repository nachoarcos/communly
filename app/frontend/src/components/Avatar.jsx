export default function Avatar({ src, size = 24 }) {
  return (
    <span
      style={{
        display: "inline-block",
        width: size,
        height: size,
        minWidth: size,
        borderRadius: "50%",
        overflow: "hidden",
        background: "var(--color-surface)",
        border: "1px solid var(--color-border)",
        verticalAlign: "middle",
      }}
    >
      {src && (
        // eslint-disable-next-line jsx-a11y/alt-text
        <img
          src={src}
          style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
        />
      )}
    </span>
  );
}
