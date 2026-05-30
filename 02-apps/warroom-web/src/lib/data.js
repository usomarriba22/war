export const RESOURCE_META = {
  supplies: { label: "Supplies", short: "SUP", target: 5000 },
  components: { label: "Components", short: "CMP", target: 4500 },
  fuel: { label: "Fuel", short: "FUL", target: 3500 },
  electronics: { label: "Electronics", short: "ELC", target: 2500 },
  rares: { label: "Rares", short: "RAR", target: 1800 },
  manpower: { label: "Manpower", short: "MAN", target: 3000 },
  money: { label: "Money", short: "MON", target: 20000 }
};

export const STORAGE_KEY = "con-war-room-games-v08";
export const API_BASE = "http://127.0.0.1:8000";

export function baseGame(id, name, country) {
  return {
    id,
    name,
    country,
    day: 1,
    victory_points: "0 / 5920",
    phase: "early expansion",
    coalition: [],
    resources: {
      supplies: { value: 0, hour: 0, status: "critical" },
      components: { value: 0, hour: 0, status: "critical" },
      fuel: { value: 0, hour: 0, status: "critical" },
      electronics: { value: 0, hour: 0, status: "critical" },
      rares: { value: 0, hour: 0, status: "critical" },
      manpower: { value: 0, hour: 0, status: "critical" },
      money: { value: 0, hour: 0, status: "critical" }
    },
    fronts: [
      { name: "Frente 1", state: "pendiente", risk: "medium", action: "actualizar" }
    ],
    stacks: [
      {
        name: "Stack principal",
        location: "capital / frente",
        units: "infanteria, recon",
        mission: "defensa",
        condition: "100%",
        threat: "medium",
        notes: "actualizar manualmente"
      }
    ],
    enemy: [
      {
        location: "frente enemigo",
        observed: "infanteria / desconocido",
        risk: "medium",
        counter: "recon + artilleria + cobertura aerea"
      }
    ],
    research: [],
    notes: "",
    snapshots: [],
    feed: [],
    updated_at: new Date().toISOString(),
    live_base_at: new Date().toISOString()
  };
}

export function seedGames() {
  const g = baseGame("colombia-main", "Colombia Principal", "Colombia");
  g.day = 2;
  g.victory_points = "432 / 5920";
  g.coalition = ["Venezuela", "USA", "Canada", "Bolivia"];
  g.resources = {
    supplies: { value: 7079, hour: 91, status: "stable" },
    components: { value: 5474, hour: 45, status: "stable" },
    fuel: { value: 345, hour: 50, status: "critical" },
    electronics: { value: 719, hour: 49, status: "low" },
    rares: { value: 84, hour: 34, status: "critical" },
    manpower: { value: 3557, hour: 48, status: "stable" },
    money: { value: 32968, hour: 382, status: "stable" }
  };
  g.fronts = [
    { name: "Panama", state: "ocupado", risk: "medium", action: "mantener guarnicion" },
    { name: "Ecuador / Quito", state: "ofensiva activa", risk: "high", action: "cerrar y estabilizar" },
    { name: "Peru", state: "siguiente objetivo posible", risk: "medium", action: "no atacar aun" },
    { name: "Caribe", state: "vigilancia naval", risk: "medium", action: "preparar fragatas" }
  ];
  g.stacks = [
    { name: "Grupo Quito", location: "Ecuador/Quito", units: "infanteria + recon", mission: "tomar capital", condition: "70%", threat: "high", notes: "no sobreextender" },
    { name: "Guarnicion Panama", location: "Panama", units: "infanteria", mission: "control urbano", condition: "100%", threat: "medium", notes: "evitar insurgencia" }
  ];
  g.enemy = [
    { location: "Quito", observed: "defensa urbana probable", risk: "high", counter: "rodear, esperar organizacion, no entrar con unidades danadas" },
    { location: "Caribe", observed: "naval desconocido", risk: "medium", counter: "radar + fragatas; no enviar transporte solo" }
  ];
  g.research = ["Radar movil", "Antiaereo movil/SAM", "Fragata", "Railgun", "Satelite", "Submarino elite"];
  return [
    g,
    baseGame("slot-2", "Partida 2", "Pendiente"),
    baseGame("slot-3", "Partida 3", "Pendiente"),
    baseGame("slot-4", "Partida 4", "Pendiente")
  ];
}

export function deriveStatus(key, value) {
  const target = RESOURCE_META[key]?.target || 1000;
  if (Number(value || 0) < target * 0.25) return "critical";
  if (Number(value || 0) < target * 0.55) return "low";
  return "stable";
}

export function readinessScore(game) {
  let score = 100;
  Object.values(game.resources || {}).forEach((r) => {
    if (r.status === "critical") score -= 12;
    if (r.status === "low") score -= 6;
  });
  (game.fronts || []).forEach((f) => {
    if (f.risk === "critical") score -= 18;
    if (f.risk === "high") score -= 10;
    if (f.risk === "medium") score -= 4;
  });
  return Math.max(0, Math.min(100, score));
}

export function normalizeGame(game) {
  const b = baseGame(game.id || `game-${Date.now()}`, game.name || "Partida", game.country || "Pais");
  return {
    ...b,
    ...game,
    resources: { ...b.resources, ...(game.resources || {}) },
    fronts: game.fronts || b.fronts,
    stacks: game.stacks || b.stacks,
    enemy: game.enemy || b.enemy,
    research: game.research || [],
    snapshots: game.snapshots || [],
    feed: game.feed || []
  };
}
