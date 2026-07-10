import type { APIRoute } from "astro";
import { supabase } from "../../lib/supabaseClient";

export const GET: APIRoute = async () => {
  try {
    const { data, error } = await supabase.rpc("contador_personas");

    if (error) {
      return new Response(JSON.stringify({ contador: 0, error: error.message }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ contador: data }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ contador: 0, error: "Error interno" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
};
