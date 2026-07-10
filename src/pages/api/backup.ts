import type { APIRoute } from "astro";
import { createSupabaseAdmin } from "../../lib/supabaseAdmin";

export const GET: APIRoute = async ({ request }) => {
  const authHeader = request.headers.get("authorization");
  const expectedSecret = import.meta.env.BACKUP_SECRET || "sos-la-victoria-backup-2026";

  if (authHeader !== `Bearer ${expectedSecret}`) {
    return new Response(JSON.stringify({ error: "No autorizado" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createSupabaseAdmin();

    const { data: personas, error: err1 } = await supabase
      .from("personas")
      .select("*")
      .order("created_at", { ascending: false });

    const { data: refugios, error: err2 } = await supabase
      .from("refugios")
      .select("*")
      .order("nombre");

    const { data: noticias, error: err3 } = await supabase
      .from("noticias")
      .select("*")
      .order("created_at", { ascending: false });

    if (err1 || err2 || err3) {
      return new Response(JSON.stringify({ error: "Error al leer datos" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const backup = {
      fecha: new Date().toISOString(),
      personas: personas || [],
      refugios: refugios || [],
      noticias: noticias || [],
    };

    return new Response(JSON.stringify(backup, null, 2), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="backup-${new Date().toISOString().split("T")[0]}.json"`,
      },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: "Error interno" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
};
