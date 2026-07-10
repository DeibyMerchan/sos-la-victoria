import type { APIRoute } from "astro";
import { supabase } from "../../lib/supabaseClient";

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const { canal, ubicacion } = body;

    const { error } = await supabase.from("solicitudes_sos").insert({
      canal: canal || "whatsapp",
      ubicacion: ubicacion || null,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: "Error interno" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
};
