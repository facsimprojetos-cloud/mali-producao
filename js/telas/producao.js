import { db, tem } from '../app.js';
import { h, num, data, dataHora, chip, chamar, ler, cadastros, toast, minutos, formModal, hojeISO, confirmar } from '../util.js';

let aba = 'apontar';
let dia = '';

export async function render(el) {
  const pode = tem('producao');
  el.innerHTML = `
    <div class="cab"><div><h1>Produção Interna</h1><p>Apontamento por operador e operação (tempo padrão do roteiro), pausas e eficiência. Os lotes chegam aqui quando enviados para "PRODUÇÃO INTERNA".</p></div></div>
    <div class="abas">
      <button data-a="apontar" class="${aba === 'apontar' ? 'ativo' : ''}">Operadores</button>
      <button data-a="lotes" class="${aba === 'lotes' ? 'ativo' : ''}">Lotes em produção</button>
      <button data-a="eficiencia" class="${aba === 'eficiencia' ? 'ativo' : ''}">Eficiência</button>
    </div><div id="alvo"></div>`;
  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); });
  const alvo = el.querySelector('#alvo');
  if (aba === 'lotes') return renderLotes(alvo);
  if (aba === 'eficiencia') return renderEficiencia(alvo, el);

  const cad = await cadastros(db, true);
  const [abertos, pausas, hoje, lotes] = await Promise.all([
    ler(db.from('v_apontamentos').select('*').is('fim', null)),
    ler(db.from('v_pausas').select('*').is('fim', null)),
    ler(db.from('v_eficiencia_dia').select('*').eq('dia', hojeISO())),
    ler(db.from('v_lotes_internos').select('*').order('criado_em')),
  ]);
  const operadores = cad.operadores.filter(o => o.ativo);
  alvo.innerHTML = `<div class="lista-cards">${operadores.map(o => {
    const ap = abertos.find(a => a.operador_id === o.id), pz = pausas.find(p => p.operador_id === o.id), ef = hoje.find(e => e.operador_id === o.id);
    return `<div class="item">
      <div class="linha1"><div><div class="tit">${h(o.nome)}</div>
        <div class="det">Hoje: <b>${num(ef?.pecas || 0)}</b> peças · ${ef?.eficiencia != null ? `eficiência <b>${num(ef.eficiencia, 1)}%</b>` : 'sem eficiência ainda'}</div></div>
        ${pz ? chip('Em pausa', 'alerta') : ap ? chip('Produzindo', 'ok') : chip('Livre')}</div>
      ${ap ? `<div class="det" style="margin-top:8px"><b>${h(ap.processo)}</b> · ${h(ap.lote)} ${h(ap.produto)} ${h(ap.cor)} ${h(ap.tamanho)}<br>desde ${dataHora(ap.inicio)} (${minutos(ap.minutos)})</div>` : ''}
      ${pz ? `<div class="det" style="margin-top:6px">Pausa: <b>${h(pz.motivo)}</b> desde ${dataHora(pz.inicio)} (${minutos(pz.minutos)})</div>` : ''}
      ${pode ? `<div class="acoes" style="margin-top:10px">
        ${!ap ? `<button class="btn pri peq" data-ini="${o.id}" ${lotes.length ? '' : 'disabled title="Nenhum lote na produção interna"'}>▶ Iniciar operação</button>` : `<button class="btn pri peq" data-fim="${ap.id}">✔ Finalizar</button><button class="btn peq perigo" data-canc="${ap.id}">Cancelar</button>`}
        ${pz ? `<button class="btn peq" data-ret="${pz.id}">Retomar</button>` : `<button class="btn peq" data-pausa="${o.id}">⏸ Pausa</button>`}
      </div>` : ''}</div>`;
  }).join('') || '<div class="vazio">Cadastre os operadores em Cadastros.</div>'}</div>`;

  alvo.querySelectorAll('[data-ini]').forEach(b => b.onclick = () => iniciar(+b.dataset.ini, lotes, () => render(el)));
  alvo.querySelectorAll('[data-fim]').forEach(b => b.onclick = async () => {
    const ap = abertos.find(a => a.id === b.dataset.fim);
    const lote = lotes.find(l => l.envio_id === ap.envio_id);
    const resta = lote ? lote.qtd - ((lote.roteiro.find(r => r.processo_id === ap.processo_id) || {}).feito || 0) : null;
    const v = await formModal({ titulo: `Finalizar ${ap.processo}`, texto: `${h(ap.operador)} · ${h(ap.lote)}${resta != null ? ` · restam <b>${resta}</b> peças nesta operação` : ''}`, botao: 'Finalizar',
      campos: [{ k: 'qtd', r: 'Peças feitas', tipo: 'number', min: 1, max: resta ?? undefined, valor: resta ?? '', req: true }] });
    if (v && await chamar(db, 'finalizar_apontamento', { p_apontamento_id: ap.id, p_qtd: v.qtd })) { toast('Apontamento registrado.', 'ok'); render(el); }
  });
  alvo.querySelectorAll('[data-canc]').forEach(b => b.onclick = async () => {
    if (await confirmar('Cancelar operação', 'Descartar este apontamento em andamento?', 'Descartar', 'perigo') && await chamar(db, 'cancelar_apontamento', { p_apontamento_id: b.dataset.canc })) { toast('Cancelado.', 'ok'); render(el); }
  });
  alvo.querySelectorAll('[data-pausa]').forEach(b => b.onclick = async () => {
    const v = await formModal({ titulo: 'Iniciar pausa', botao: 'Pausar', campos: [
      { k: 'mot', r: 'Motivo', tipo: 'select', opcoes: cad.motivos.filter(m => m.ativo).map(m => [m.id, m.nome + (m.duracao_min ? ` (${m.duracao_min} min)` : '')]), req: true },
      { k: 'obs', r: 'Observação' }] });
    if (v && await chamar(db, 'iniciar_pausa', { p_operador_id: +b.dataset.pausa, p_motivo_id: +v.mot, p_obs: v.obs })) { toast('Pausa iniciada.', 'ok'); render(el); }
  });
  alvo.querySelectorAll('[data-ret]').forEach(b => b.onclick = async () => {
    if (await chamar(db, 'encerrar_pausa', { p_pausa_id: b.dataset.ret })) { toast('Pausa encerrada.', 'ok'); render(el); }
  });
}

async function iniciar(operadorId, lotes, depois) {
  const v = await formModal({ titulo: 'Iniciar operação', botao: 'Iniciar', campos: [
    { k: 'lote', r: 'Lote', tipo: 'select', req: true, opcoes: lotes.map(l => [l.envio_id, `${l.lote} · ${l.produto} ${l.cor} ${l.tamanho} (${l.qtd} pç)`]) },
    { k: 'proc', r: 'Operação', tipo: 'select', req: true, opcoes: [] }],
    aoAbrir: (m) => {
      const sl = m.querySelector('[name=lote]'), sp = m.querySelector('[name=proc]');
      const enche = () => {
        const l = lotes.find(x => x.envio_id === sl.value);
        sp.innerHTML = '<option value="">Selecione…</option>' + (l ? l.roteiro.map(r => `<option value="${r.processo_id}" ${r.feito >= l.qtd ? 'disabled' : ''}>${r.sequencia}. ${h(r.processo)} — ${r.feito}/${l.qtd}${r.feito >= l.qtd ? ' ✔' : ''}</option>`).join('') : '');
        if (l && !l.roteiro.length) sp.innerHTML = '<option value="">Produto sem roteiro — cadastre em Ficha Técnica</option>';
      };
      sl.onchange = enche; enche();
    } });
  if (v && await chamar(db, 'iniciar_apontamento', { p_operador_id: operadorId, p_envio_id: v.lote, p_processo_id: +v.proc })) { toast('Operação iniciada.', 'ok'); depois(); }
}

async function renderLotes(alvo) {
  const lotes = await ler(db.from('v_lotes_internos').select('*').order('criado_em'));
  alvo.innerHTML = `<div class="lista-cards">${lotes.map(l => {
    const total = l.tempo_peca_seg * l.qtd, pct = total ? Math.min(100, Math.round(100 * l.seg_produzidos / total)) : 0;
    return `<div class="item">
      <div class="linha1"><div><div class="tit">${h(l.lote)}</div><div class="det">${h(l.produto)} · ${h(l.cor)} · ${h(l.tamanho)} · <b>${l.qtd}</b> peças · previsão ${data(l.previsao)}</div></div>${chip(pct + '%', pct >= 100 ? 'ok' : 'info')}</div>
      <div class="barra"><div style="width:${pct}%"></div></div>
      <div class="tabela-wrap" style="margin-top:8px"><table><thead><tr><th>#</th><th>Operação</th><th class="n">Tempo (s)</th><th class="n">Feito</th></tr></thead>
        <tbody>${l.roteiro.map(r => `<tr><td>${r.sequencia}</td><td>${h(r.processo)}</td><td class="n">${num(r.tempo_seg)}</td><td class="n">${r.feito >= l.qtd ? chip(`${r.feito}/${l.qtd}`, 'ok') : `${r.feito}/${l.qtd}`}</td></tr>`).join('') || '<tr><td colspan="4" class="vazio">Produto sem roteiro cadastrado.</td></tr>'}</tbody></table></div>
      <p class="muted peq">Quando terminar, finalize o lote em <a href="#/faccao">Gestão de Facção → Produção interna</a>.</p></div>`;
  }).join('') || '<div class="vazio">Nenhum lote na produção interna.</div>'}</div>`;
}

async function renderEficiencia(alvo, el) {
  const de = new Date(Date.now() - 30 * 86400000).toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  const ef = await ler(db.from('v_eficiencia_dia').select('*').gte('dia', de).order('dia', { ascending: false }).order('operador'));
  const d = dia || hojeISO();
  const aps = await ler(db.from('v_apontamentos').select('*').eq('dia', d).not('fim', 'is', null).order('inicio'));
  alvo.innerHTML = `
    <div class="card"><h2>Últimos 30 dias</h2><div class="tabela-wrap"><table><thead><tr><th>Dia</th><th>Operador</th><th class="n">Peças</th><th class="n">Min. padrão</th><th class="n">Min. apontados</th><th class="n">Pausas</th><th class="n">Eficiência</th></tr></thead>
      <tbody>${ef.map(x => `<tr><td>${data(x.dia)}</td><td>${h(x.operador)}</td><td class="n">${num(x.pecas)}</td><td class="n">${num(x.min_padrao, 1)}</td><td class="n">${num(x.min_apontados, 1)}</td><td class="n">${num(x.min_pausas, 1)}</td>
        <td class="n">${x.eficiencia != null ? chip(num(x.eficiencia, 1) + '%', x.eficiencia >= 85 ? 'ok' : x.eficiencia >= 60 ? 'alerta' : 'erro') : '—'}</td></tr>`).join('') || '<tr><td colspan="7" class="vazio">Sem apontamentos.</td></tr>'}</tbody></table></div></div>
    <div class="card" style="margin-top:14px"><div class="linha1"><h2>Apontamentos do dia</h2><label class="campo"><input type="date" id="dia" value="${d}"></label></div>
      <div class="tabela-wrap"><table><thead><tr><th>Operador</th><th>Operação</th><th>Lote</th><th>Início</th><th>Fim</th><th class="n">Peças</th><th class="n">Min. padrão</th><th class="n">Min. reais</th></tr></thead>
      <tbody>${aps.map(a => `<tr><td>${h(a.operador)}</td><td>${h(a.processo)}</td><td>${h(a.lote)}</td><td>${dataHora(a.inicio)}</td><td>${dataHora(a.fim)}</td>
        <td class="n">${num(a.qtd)}</td><td class="n">${num(a.minutos_padrao, 1)}</td><td class="n">${num(a.minutos, 1)}</td></tr>`).join('') || '<tr><td colspan="8" class="vazio">Nenhum apontamento neste dia.</td></tr>'}</tbody></table></div></div>`;
  alvo.querySelector('#dia').onchange = (e) => { dia = e.target.value; render(el); };
}
