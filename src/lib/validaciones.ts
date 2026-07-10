export interface PersonaForm {
  cedula: string;
  sin_cedula: boolean;
  nombres: string;
  apellidos: string;
  telefono: string;
  sector: string;
  direccion: string;
  acompanantes: number;
  estado: "en_vivienda" | "evacuado" | "en_refugio";
  refugio_id: string | null;
  observaciones: string;
}

export function validarPersonaForm(data: PersonaForm): string | null {
  if (!data.nombres.trim()) return "El nombre es obligatorio";
  if (!data.apellidos.trim()) return "El apellido es obligatorio";
  if (!data.sin_cedula && !data.cedula.trim()) return "La cédula es obligatoria";
  if (
    !data.sin_cedula &&
    !/^\d{5,10}$/.test(data.cedula.replace(/[^0-9]/g, ""))
  )
    return "La cédula debe tener entre 5 y 10 dígitos numéricos";
  if (data.acompanantes < 0) return "El número de acompañantes no puede ser negativo";
  return null;
}

export function generarCedulaTemporal(): string {
  return `SINCED-${Date.now()}`;
}
