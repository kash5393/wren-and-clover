import { getProductImage } from "@/lib/product-images";

export async function GET(
  _request: Request,
  context: RouteContext<"/product-images/[id]">
): Promise<Response> {
  const { id } = await context.params;
  const image = await getProductImage(id);

  if (!image) {
    return new Response("Not found", { status: 404 });
  }

  return new Response(new Uint8Array(image.data), {
    headers: {
      "Content-Type": image.contentType,
      "Content-Length": String(image.data.length),
      "Cache-Control": "public, max-age=31536000, immutable",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
