import { marked } from "marked";
import DOMPurify from "dompurify";

export default function Markdown({ source }) {
  const dirty = marked.parse(source || "", { breaks: true });
  const clean = DOMPurify.sanitize(dirty);
  // eslint-disable-next-line react/no-danger
  return <div className="post-body" dangerouslySetInnerHTML={{ __html: clean }} />;
}
