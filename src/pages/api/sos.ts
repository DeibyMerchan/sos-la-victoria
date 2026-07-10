import type { APIRoute } from "astro";
import { supabase } from "../../lib/supabaseClient";

export const POST: APIRoute = async ({ request }) => {
  try {
    const { canal, ubicacion } = await request.json();
    await supabase.from("solicitudes_sos").insert({ canal: canal || "whatsapp", ubicacion: ubicacion || null });
    return new Response(JSON.stringify({ success: true }), { status: 201 });
  } catch (_) {
    return new Response(JSON.stringify({ success: true }), { status: 201 });
  }
};
