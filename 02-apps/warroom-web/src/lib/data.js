export const RESOURCE_KEYS = ["supplies", "components", "fuel", "electronics", "rares", "manpower", "money"];

export const RESOURCE_META = {
  supplies: { label: "Supplies", short: "SUP", img: "/assets/resources/supplies.svg", target: 5000 },
  components: { label: "Components", short: "CMP", img: "/assets/resources/components.svg", target: 4500 },
  fuel: { label: "Fuel", short: "FUL", img: "/assets/resources/fuel.svg", target: 3500 },
  electronics: { label: "Electronics", short: "ELC", img: "/assets/resources/electronics.svg", target: 2500 },
  rares: { label: "Rares", short: "RAR", img: "/assets/resources/rares.svg", target: 1800 },
  manpower: { label: "Manpower", short: "MAN", img: "/assets/resources/manpower.svg", target: 3000 },
  money: { label: "Money", short: "MON", img: "/assets/resources/money.svg", target: 20000 }
};

export const STORAGE_KEY = "con-war-room-games-v09";
export const API_BASE = "http://127.0.0.1:8000";

export function deriveStatus(key, value) {
  const target = RESOURCE_META[key]?.target || 1000;
  const n = Number(value || 0);
  if (n < target * 0.25) return "critical";
  if (n < target * 0.55) return "low";
  return "stable";
}

export function baseGame(id, name, country) {
  return {
    id,
    name,
    country,
    day: 1,
    victory_points: "0 / 5920",
    phase: "early expansion",
    coalition: [],
    resources: Object.fromEntries(RESOURCE_KEYS.map(k => [k, { value: 0, hour: 0, status: "critical" }])),
    fronts: [{ name: "Frente 1", state: "pendiente", risk: "medium", action: "actualizar" }],
    stacks: [
      { name: "Stack principal", location: "capital / frente", units: "infanteria + recon", mission: "defensa", condition: "100%", threat: "medium", order: "mantener" }
    ],
    enemy: [
      { location: "frente enemigo", observed: "desconocido", risk: "medium", counter: "recon + radar antes de atacar" }
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
  g.day = 6;
  g.victory_points = "550 / 5920";
  g.coalition = ["Venezuela", "USA", "Canada", "Bolivia"];
  g.resources = {
    supplies: { value: 1857, hour: 119, status: "low" },
    components: { value: 2704, hour: 69, status: "stable" },
    fuel: { value: 928, hour: 64, status: "low" },
    electronics: { value: 481, hour: 60, status: "critical" },
    rares: { value: 217, hour: 43, status: "critical" },
    manpower: { value: 1206, hour: 49, status: "low" },
    money: { value: 13764, hour: 485, status: "low" }
  };
  g.fronts = [
    { name: "Panama", state: "ocupado", risk: "medium", action: "mantener guarnicion" },
    { name: "Ecuador / Quito", state: "ofensiva activa", risk: "high", action: "cerrar y estabilizar" },
    { name: "Peru", state: "siguiente objetivo posible", risk: "medium", action: "no atacar aun" },
    { name: "Caribe", state: "vigilancia naval", risk: "medium", action: "preparar fragatas" }
  ];
  g.stacks = [
    { name: "Grupo Quito", location: "Ecuador / Quito", units: "infanteria + recon", mission: "tomar ciudad", condition: "70%", threat: "high", order: "avanzar con cautela" },
    { name: "Guarnicion Panama", location: "Panama", units: "infanteria", mission: "control urbano", condition: "100%", threat: "medium", order: "mantener" }
  ];
  g.enemy = [
    { location: "Quito", observed: "defensa urbana probable", risk: "high", counter: "rodear, esperar organizacion, no entrar con unidades danadas" },
    { location: "Caribe", observed: "naval desconocido", risk: "medium", counter: "radar + fragatas; no enviar transporte solo" }
  ];
  g.research = ["Radar movil", "Antiaereo movil/SAM", "Fragata", "Railgun", "Satelite", "Submarino elite"];
  return [g, baseGame("slot-2", "Partida 2", "Pendiente"), baseGame("slot-3", "Partida 3", "Pendiente"), baseGame("slot-4", "Partida 4", "Pendiente")];
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

export function readinessScore(game) {
  let score = 100;
  Object.values(game.resources || {}).forEach(r => {
    if (r.status === "critical") score -= 12;
    if (r.status === "low") score -= 6;
  });
  (game.fronts || []).forEach(f => {
    if (f.risk === "critical") score -= 18;
    if (f.risk === "high") score -= 10;
    if (f.risk === "medium") score -= 4;
  });
  return Math.max(0, Math.min(100, score));
}