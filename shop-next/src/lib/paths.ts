/** Only allows redirects to pages on this site, never to another website. */
export function safeNextPath(value: unknown): string {
  if (typeof value === "string" && value.startsWith("/") && !value.startsWith("//")) {
    return value;
  }
  return "/";
}
