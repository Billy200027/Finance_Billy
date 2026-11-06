import { money, simulate } from '../domain.js';

const host = document.querySelector('#bm-demo');
const dateLabel = new Intl.DateTimeFormat('es-EC', {
  weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC'
});
const WEEK = 7 * 86400000;
const LOAN_RATE = 0.0115;
const PELADO_RATES = [
  ['Grande', 0.11], ['Mediano', 0.14], ['Pequeño', 0.22], ['PCC / tijera', 0.08]
];

function numberField(label, name, value, min, step = 1, max) {
  return `<label>${label}<input name="${name}" type="number" value="${value}" min="${min}" step="${step}" ${max === undefined ? '' : `max="${max}"`} required></label>`;
}

function metric(label, value) {
  return `<div><dt>${label}</dt><dd>${value}</dd></div>`;
}

function calculator(title, intro, controls, compute, footnote) {
  host.innerHTML = `<h2>${title}</h2><p>${intro}</p>
    <form autocomplete="off"><div class="bm-demo-fields">${controls}</div></form>
    <div class="bm-demo-summary" aria-live="polite"></div>${footnote}`;
  const form = host.querySelector('form');
  const result = host.querySelector('.bm-demo-summary');
  const update = () => {
    const values = Object.fromEntries(new FormData(form));
    const state = compute(values, form);
    result.innerHTML = state.error ? `<p>${state.error}</p>` : `<dl>${state.metrics}</dl>`;
    state.updateDetails?.();
  };
  form.addEventListener('input', update);
  form.addEventListener('submit', event => event.preventDefault());
  update();
}

function finance() {
  calculator('Simula un préstamo', 'Cambia el monto y el plazo para ver cuánto pagarías cada semana.',
    numberField('Monto del préstamo (USD)', 'amount', 125, 40, 5) +
    numberField('Plazo (5 a 20 semanas)', 'weeks', 20, 5, 1, 20),
    ({ amount, weeks }) => {
      try {
        const loan = simulate(amount, weeks, LOAN_RATE);
        if (!Number.isSafeInteger(Number(amount) * 100) || !Number.isFinite(loan.total)) throw new Error();
        return { metrics: [
          ['Cuota semanal estimada', money(loan.payment)], ['Interés total', money(loan.interest)],
          ['Total a devolver', money(loan.total)], ['Última cuota', money(loan.last)],
          ['Tasa semanal de referencia', '1,15 %']
        ].map(([label, value]) => metric(label, value)).join('') };
      } catch {
        return { error: 'Ingresa un monto desde $40 en múltiplos de $5 y un plazo entero de 5 a 20 semanas.' };
      }
    }, '<p class="bm-demo-note">La última cuota ajusta los centavos. La tasa es la de referencia de esta demo. La app confirma las condiciones y fechas al tramitar el préstamo.</p>');
}

// Model an example posted on a Saturday in Ecuador, with the first contribution a week later.
function nextRegistrationSaturday(now) {
  const local = new Date(now.getTime() - 5 * 3600000);
  const offset = (6 - local.getUTCDay() + 7) % 7;
  return Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + offset);
}

function cuadros() {
  const registration = nextRegistrationSaturday(new Date());
  const date = (week, day = 0) => dateLabel.format(registration + week * WEEK + day * 86400000);
  const controls = numberField('Aporte semanal ($5 a $30)', 'amount', 6, 5, 0.01, 30) +
    '<label>Duración del cuadro <output for="bm-demo-weeks">25 semanas</output><input name="weeks" id="bm-demo-weeks" type="range" value="25" min="5" max="25" step="1"></label>';
  calculator('Simula un cuadro', 'Elige tu aporte y mueve el deslizador para ver cuánto recibirías en tu turno.',
    controls, ({ amount, weeks }, form) => {
      form.querySelector('output').textContent = weeks + ' semanas';
      const valid = form.elements.amount.validity.valid;
      const total = Math.round(Number(amount) * 100) * Number(weeks);
      return {
        ...(valid ? { metrics:
          metric('Recibes en tu turno', money(total / 100)) +
          metric('Aportas cada semana', money(amount)) +
          metric('Total de aportes', money(total / 100)) +
          metric('Multa diaria por atraso', money(Math.round(total * 0.005) / 100))
        } : { error: 'Ingresa un aporte semanal entre $5 y $30, con hasta dos decimales.' }),
        updateDetails() {
          host.querySelector('tbody').innerHTML = Array.from({ length: Number(weeks) }, (_, i) =>
            `<tr><th scope="row">${i + 1}</th><td>${date(i + 1)}</td><td>${date(i + 1, 1)}</td></tr>`
          ).join('');
        }
      };
    }, `<p class="bm-demo-note">También aportas en la semana de tu turno. La multa diaria es el 0,5 % de la entrega total, desde el domingo a las 12:00 si el aporte está incompleto.</p>
    <details><summary>Ver calendario de ejemplo</summary>
      <p class="bm-demo-note">Semana 0 · Inscripciones desde el ${date(0)}. En este ejemplo el cierre programado cae el jueves o viernes (${date(0, 5)} o ${date(0, 6)}), o antes si se llenan los cupos.</p>
      <p class="bm-demo-note">En cada turno puedes aportar el sábado o el domingo antes del mediodía. La entrega del turno es el domingo de 12:00 a 23:59, hora de Ecuador.</p>
      <div class="bm-demo-table" tabindex="0" role="region" aria-label="Calendario de turnos"><table>
        <thead><tr><th scope="col">Turno</th><th scope="col">Inicio de aporte</th><th scope="col">Entrega</th></tr></thead><tbody></tbody>
      </table></div>
    </details>`);
}

function pelado() {
  const controls = PELADO_RATES.map(([label, rate], i) =>
    numberField(`${label} · ${money(rate)}/lb`, 'trays' + i, [4, 3, 2, 1][i], 0)
  ).join('') + numberField('Libras totales del día', 'pounds', 100, 0, 0.01) +
    '<label>Turno<select name="shift"><option value="day">Mañana</option><option value="night">Noche (+$0,01/lb)</option></select></label>' +
    '<label class="bm-demo-check"><input type="checkbox" name="holiday"> Día feriado (tarifa doble)</label>';
  calculator('Calcula un día de pelado', 'Pon las bandejas de cada tipo y el peso total para estimar el pago de esa jornada.',
    controls, (values, form) => {
      const trays = PELADO_RATES.map((_, i) => Number(values['trays' + i]));
      const count = trays.reduce((sum, n) => sum + n, 0);
      const pounds = Number(values.pounds);
      if (!form.checkValidity() || !Number.isSafeInteger(count) || !Number.isSafeInteger(Math.round(pounds * 100))) {
        return { error: 'Usa bandejas enteras y libras positivas o cero, con hasta dos decimales.' };
      }
      if (Boolean(count) !== Boolean(pounds)) {
        return { error: 'Indica tanto el total de libras como las bandejas que hiciste.' };
      }
      // Match PeladoCore.calculateDay: assign pounds proportionally and truncate each subtotal.
      const truncate = value => Math.floor((value + Number.EPSILON) * 100) / 100;
      const perTray = count ? pounds / count : 0;
      const subtotals = PELADO_RATES.map(([label, rate], i) => {
        const effectiveRate = (rate + (values.shift === 'night' ? 0.01 : 0)) * (values.holiday ? 2 : 1);
        return { label, lbs: trays[i] * perTray, pay: truncate(trays[i] * perTray * effectiveRate) };
      });
      const total = truncate(subtotals.reduce((sum, item) => sum + item.pay, 0));
      return { metrics: metric('Pago estimado por pelado', money(total)) + metric('Total de bandejas', count) +
        subtotals.map(item => metric(`${item.label} · ${item.lbs.toLocaleString('es-EC', { maximumFractionDigits: 2 })} lb`, money(item.pay))).join('') };
    }, '<p class="bm-demo-note">Como en Pelado Unificado, las libras se reparten según la cantidad de bandejas. La estimación usa las tarifas base y cubre el pago por producción de un día.</p>');
}

function sly() {
  host.innerHTML = `<h2>Prueba cómo funciona SLY</h2>
    <p>Pega el enlace de ejemplo y elige Video o Audio. Esta demostración imita la descarga dentro de la ficha.</p>
    <div class="bm-sly-demo">
      <label for="bm-sly-url">Enlace de ejemplo</label>
      <input id="bm-sly-url" type="text" placeholder="Pulsa Pegar ejemplo" readonly>
      <div class="bm-sly-buttons">
        <button type="button" class="bm-secondary" data-sly="paste">Pegar ejemplo</button>
        <button type="button" class="bm-primary" data-sly="video" disabled>Video</button>
        <button type="button" class="bm-primary" data-sly="audio" disabled>Audio</button>
      </div>
      <progress max="100" value="0" hidden aria-label="Progreso de la descarga simulada"></progress>
      <p class="bm-demo-note" role="status">La demo no descarga archivos ni se conecta a redes sociales.</p>
    </div>`;
  const input = host.querySelector('input');
  const status = host.querySelector('[role="status"]');
  const progress = host.querySelector('progress');
  const [paste, video, audio] = host.querySelectorAll('[data-sly]');
  paste.onclick = () => {
    input.value = 'https://ejemplo.invalid/video';
    video.disabled = audio.disabled = false;
    status.textContent = 'Enlace listo. Elige Video o Audio.';
  };
  for (const button of [video, audio]) {
    button.onclick = () => {
      paste.disabled = video.disabled = audio.disabled = true;
      progress.hidden = false;
      progress.value = 0;
      status.textContent = 'Simulando la descarga de ' + button.textContent.toLowerCase() + '…';
      const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const finish = () => {
        progress.value = 100;
        paste.disabled = video.disabled = audio.disabled = false;
        const extension = button === video ? 'mp4' : 'm4a';
        status.textContent = `Listo en la simulación · Descargas / SLY / ejemplo.${extension}`;
      };
      if (reduceMotion) { finish(); return; }
      const start = performance.now();
      const frame = now => {
        if (!progress.isConnected) return;
        progress.value = Math.min(100, (now - start) / 14);
        if (progress.value === 100) finish();
        else requestAnimationFrame(frame);
      };
      requestAnimationFrame(frame);
    };
  }
}

const demos = new Map([
  ['finance-billy', finance], ['cuadros-app', cuadros], ['pelado-unificado', pelado], ['sly', sly]
]);
let active;
function renderDemo() {
  const detail = document.querySelector('#bm-detail');
  const slug = detail.hidden ? undefined : detail.dataset.app;
  const demo = demos.get(slug);
  if (active === demo) return;
  active = demo;
  host.replaceChildren();
  host.hidden = !demo;
  if (demo) demo();
}
window.addEventListener('hashchange', renderDemo);
renderDemo();
