import { db, tem } from '../app.js';
import { h, num, data, dataHora, chip, modal, chamar, ler, cadastros, opcoes, toast, pedirTexto, contem, minutos, formModal, ops, DESTINOS } from '../util.js';

const estado = {};   // por tipo: { aba, busca }
const TITULO = { 'ESTAMPARIA': 'Estamparia', 'FINALIZAÇÃO': 'Finalização interna', 'INSPEÇÃO': 'Inspeção' };
const DESCR = {
  'ESTAMPARIA': 'Lotes que chegam para estampar: antes da costura (direto do corte) ou depois da produção. Também as OPs de estamparia feitas a partir do estoque.',
  'FINALIZAÇÃO': 'Acabamento interno das peças que voltaram das facções.',
  'INSPEÇÃO': 'Conferência de qualidade: aprovadas seguem para o estoque, com defeito voltam para conserto.',
};

export async function render(el, rota) {
  const tipo = rota.tipo;
  const st = estado[tipo] ||= { aba: 'aguardando', busca: '' };
  const perfil = tipo === 'ESTAMPARIA' ? 'estamparia' : 'qualidade';
  const pode = tem(perfil), sup = tem('supervisor');
  const abas = [['aguardando', 'Aguardando'], ['andamento', 'Em andamento'], ['concluidas', 'Concluídas']];
  if (tipo === 'ESTAMPARIA') abas.push(['ops', 'OP do estoque']);
  const cabHtml = `
    <div class="cab"><div><h1>${TITULO[tipo]}</h1><p>${DESCR[tipo]}</p></div>
      ${tipo === 'ESTAMPARIA' && st.aba === 'ops' && (tem('estamparia') || tem('estoque')) ? '<button class="btn acento" id="nova-op">+ Nova OP de estamparia</button>' : ''}</div>
    <div class="abas">${abas.map(([k, r]) => `<button data-a="${k}" class="${st.aba === k ? 'ativo' : ''}">${r}</button>`).join('')}</div>
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(st.busca)}" placeholder="Sublote, produto, cor…"></label></div>`;
  const ligar = () => {
    el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { st.aba = b.dataset.a; render(el, rota); });
    el.querySelector('#busca').onchange = (e) => { st.busca = e.target.value; render(el, rota); };
  };
  if (st.aba === 'ops') return renderOps(el, rota, cabHtml, ligar, st);

  let q = db.from('v_etapas').select('*').eq('tipo', tipo).limit(500);
  if (st.aba === 'aguardando') q = q.is('inicio', null).order('criado_em');
  if (st.aba === 'andamento') q = q.not('inicio', 'is', null).is('fim', null).order('inicio');
  if (st.aba === 'concluidas') q = q.not('fim', 'is', null).order('fim', { ascending: false }).limit(200);
  const lista = (await ler(q)).filter(x => contem(x, ['sublote', 'produto', 'cor', 'tamanho', 'faccao', 'responsavel'], st.busca));
  const grupos = new Map();
  lista.forEach(x => { if (!grupos.has(x.lote)) grupos.set(x.lote, []); grupos.get(x.lote).push(x); });

  el.innerHTML = `${cabHtml}
    <p class="muted peq">${num(lista.length)} sublote(s) · ${num(lista.reduce((a, x) => a + x.qtd, 0))} peças</p>
    <div class="tabela-wrap"><table>
      <thead><tr><th>Sublote</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th>Origem</th><th>${st.aba === 'aguardando' ? 'Chegou' : 'Início'}</th>
        ${st.aba === 'concluidas' ? '<th class="n">Aprov.</th><th class="n">Conserto</th><th class="n">Perda</th><th>Destino</th>' : '<th>Tempo</th><th>Responsável</th>'}<th></th></tr></thead>
      <tbody>${[...grupos.entries()].map(([lote, itens]) => `<tr class="grupo"><td colspan="12">Lote ${h(lote)} · ${h(itens[0].produto)} · ${num(itens.reduce((a, x) => a + x.qtd, 0))} peças
          ${pode && st.aba === 'aguardando' && itens.length > 1 ? `<button class="btn peq" data-ini-lote="${h(lote)}" style="margin-left:8px">Iniciar lote todo</button>` : ''}</td></tr>
        ${itens.map(x => `<tr>
        <td class="forte">${h(x.sublote)}</td><td>${h(x.produto)}</td><td>${h(x.cor)}</td><td>${h(x.tamanho)}</td><td class="n forte">${num(x.qtd)}</td>
        <td class="peq">${h(origem(x))}</td>
        <td>${dataHora(st.aba === 'aguardando' ? x.criado_em : x.inicio)}</td>
        ${st.aba === 'concluidas'
          ? `<td class="n">${num(x.qtd_aprovada)}</td><td class="n">${num(x.qtd_conserto)}</td><td class="n">${num(x.qtd_perda)}</td><td>${x.destino ? chip(rotDestino(x.destino)) : '—'}</td>`
          : `<td>${x.minutos != null ? minutos(x.minutos) : ''}</td><td>${h(x.responsavel || '')}</td>`}
        <td><div class="acoes">
          ${pode && !x.inicio ? `<button class="btn peq" data-ini="${x.id}">▶ Iniciar</button>` : ''}
          ${pode && !x.fim ? `<button class="btn pri peq" data-fim="${x.id}">✔ Concluir</button>` : ''}
          ${sup && x.inicio ? `<button class="btn peq perigo" data-est="${x.id}">↩</button>` : ''}
        </div></td></tr>`).join('')}`).join('') || '<tr><td colspan="12" class="vazio">Nada por aqui.</td></tr>'}</tbody></table></div>`;
  ligar();
  const acha = (id) => lista.find(x => x.id === id);
  el.querySelectorAll('[data-ini]').forEach(b => b.onclick = async () => {
    const v = await formModal({ titulo: `Iniciar ${TITULO[tipo].toLowerCase()} — ${acha(b.dataset.ini).sublote}`, botao: 'Iniciar', campos: [{ k: 'resp', r: 'Responsável (opcional)' }] });
    if (v && await chamar(db, 'iniciar_etapa', { p_etapa_id: b.dataset.ini, p_responsavel: v.resp })) { toast('Iniciado.', 'ok'); render(el, rota); }
  });
  el.querySelectorAll('[data-ini-lote]').forEach(b => b.onclick = async () => {
    const itens = lista.filter(x => x.lote === b.dataset.iniLote && !x.inicio);
    const v = await formModal({ titulo: `Iniciar lote ${b.dataset.iniLote}`, texto: `${itens.length} sublote(s) serão iniciados.`, botao: 'Iniciar todos', campos: [{ k: 'resp', r: 'Responsável (opcional)' }] });
    if (!v) return;
    for (const x of itens) if (!await chamar(db, 'iniciar_etapa', { p_etapa_id: x.id, p_responsavel: v.resp })) break;
    toast('Lote iniciado.', 'ok'); render(el, rota);
  });
  el.querySelectorAll('[data-fim]').forEach(b => b.onclick = () => concluir(acha(b.dataset.fim), () => render(el, rota)));
  el.querySelectorAll('[data-est]').forEach(b => b.onclick = async () => {
    const x = acha(b.dataset.est);
    const m = await pedirTexto(`Estornar ${x.sublote}`, x.fim ? 'A conclusão será desfeita (só se o destino ainda não usou as peças).' : 'A etapa volta para "Aguardando".', { botao: 'Estornar' });
    if (m && await chamar(db, 'estornar_etapa', { p_etapa_id: x.id, p_motivo: m })) { toast('Estornado.', 'ok'); render(el, rota); }
  });
}

function origem(x) {
  if (x.origem === 'CORTE') return 'Corte (antes da costura)';
  if (x.origem === 'RETORNO') return `Retorno ${x.faccao || ''}`;
  if (x.origem === 'CONSERTO') return `Conserto ${x.faccao || ''}`;
  return 'Etapa anterior';
}
const rotDestino = (d) => d === 'FACÇÃO' ? 'Liberado p/ costura' : DESTINOS[d];

async function concluir(x, depois) {
  const cad = await cadastros(db);
  const destinos = Object.entries(DESTINOS).filter(([k]) => k !== x.tipo);
  if (x.origem === 'CORTE') destinos.unshift(['FACÇÃO', 'Liberar para costura (facção)']);
  const padrao = x.origem === 'CORTE' ? 'FACÇÃO' : x.tipo === 'INSPEÇÃO' ? 'ESTOQUE' : 'INSPEÇÃO';
  modal({
    titulo: `Concluir ${TITULO[x.tipo].toLowerCase()} — ${x.sublote}`,
    corpo: `<p>${h(x.produto)} ${h(x.cor)} ${h(x.tamanho)} · <b>${x.qtd}</b> peças</p>
      <form id="fe" class="grade g3">
        <label class="campo">Aprovadas<input type="number" name="ap" min="0" max="${x.qtd}" value="${x.qtd}"></label>
        <label class="campo">Para conserto<input type="number" name="co" min="0" max="${x.qtd}" value="0"></label>
        <label class="campo">Perda / descarte<input type="number" name="pe" min="0" max="${x.qtd}" value="0"></label>
        <label class="campo">Destino das aprovadas<select name="dest">${destinos.map(([k, r]) => `<option value="${k}" ${k === padrao ? 'selected' : ''}>${r}</option>`).join('')}</select></label>
        <label class="campo">Facção do conserto<select name="fac">${opcoes(cad.faccoes.filter(f => f.ativo), x.faccao_id, 'nome', 'id', x.faccao_id ? undefined : 'Selecione…')}</select></label>
        <label class="campo">Observação<input name="obs"></label>
      </form>`,
    botoes: [{ texto: 'Cancelar' }, { texto: 'Concluir', classe: 'pri', acao: async (m) => {
      const f = m.querySelector('#fe'), ap = +f.ap.value || 0, co = +f.co.value || 0, pe = +f.pe.value || 0;
      if (ap + co + pe !== x.qtd) { toast(`Aprovadas + conserto + perda deve ser ${x.qtd}.`, 'erro'); return false; }
      if (co > 0 && !f.fac.value) { toast('Escolha a facção que fará o conserto.', 'erro'); return false; }
      if (!await chamar(db, 'concluir_etapa', { p_etapa_id: x.id, p_aprovada: ap, p_conserto: co, p_perda: pe, p_destino: ap > 0 ? f.dest.value : null,
        p_faccao_conserto: co > 0 ? +f.fac.value : null, p_obs: f.obs.value || null })) return false;
      toast('Concluído.', 'ok'); depois();
    } }]
  });
}

// ---------- OP de estamparia a partir do estoque ----------
async function renderOps(el, rota, cabHtml, ligar, st) {
  const lista = (await ler(db.from('v_ops_estamparia').select('*').order('data', { ascending: false }).limit(300)))
    .filter(o => contem(o, ['numero', 'produto', 'cor', 'estampa', 'pedido_numero'], st.busca));
  const pode = tem('estamparia'), sup = tem('supervisor');
  el.innerHTML = `${cabHtml}
    <div class="tabela-wrap"><table><thead><tr><th>OP</th><th>Data</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th>Estampa</th><th>Pedido</th><th>Previsão</th><th>Status</th><th></th></tr></thead>
    <tbody>${lista.map(o => `<tr><td class="forte">${o.numero}</td><td>${data(o.data)}</td><td>${h(o.produto)}</td><td>${h(o.cor)}</td><td>${h(o.tamanho)}</td>
      <td class="n">${num(o.qtd)}${o.retorno_em ? ` <span class="muted peq">(${o.qtd_retorno} ok)</span>` : ''}</td><td>${h(o.estampa || '')}</td><td>${o.pedido_numero || ''}</td>
      <td>${data(o.previsao)}</td><td>${chip(o.status, o.status === 'Concluída' ? 'ok' : o.status === 'Atrasada' ? 'erro' : 'alerta')}</td>
      <td><div class="acoes">${pode && !o.retorno_em ? `<button class="btn pri peq" data-ret="${o.id}">Retorno</button>` : ''}
        ${sup ? `<button class="btn peq perigo" data-canc="${o.id}">↩</button>` : ''}</div></td></tr>`).join('') || '<tr><td colspan="11" class="vazio">Nenhuma OP.</td></tr>'}</tbody></table></div>`;
  ligar();
  el.querySelector('#nova-op')?.addEventListener('click', () => novaOp(() => render(el, rota)));
  el.querySelectorAll('[data-ret]').forEach(b => b.onclick = async () => {
    const o = lista.find(x => x.id === b.dataset.ret);
    const v = await formModal({ titulo: `Retorno da OP ${o.numero}`, texto: `${h(o.produto)} ${h(o.cor)} ${h(o.tamanho)} · ${o.qtd} peças`, botao: 'Registrar retorno', campos: [
      { k: 'ok', r: 'Peças estampadas (voltam ao estoque)', tipo: 'number', valor: o.qtd, min: 0, max: o.qtd }, { k: 'perda', r: 'Perdidas', tipo: 'number', valor: 0, min: 0, max: o.qtd }],
      validar: (v) => (v.ok || 0) + (v.perda || 0) !== o.qtd ? `Estampadas + perdidas deve ser ${o.qtd}.` : null });
    if (v && await chamar(db, 'concluir_op_estamparia', { p_op_id: o.id, p_qtd: v.ok || 0, p_perda: v.perda || 0 })) { toast('Retorno registrado.', 'ok'); render(el, rota); }
  });
  el.querySelectorAll('[data-canc]').forEach(b => b.onclick = async () => {
    const m = await pedirTexto('Cancelar / estornar OP', 'Se a OP já retornou, o retorno é desfeito; se não, a OP é apagada e as peças voltam ao estoque.', { botao: 'Confirmar' });
    if (m && await chamar(db, 'cancelar_op_estamparia', { p_op_id: b.dataset.canc, p_motivo: m })) { toast('Feito.', 'ok'); render(el, rota); }
  });
}

export async function novaOp(depois, pre = {}) {
  const cad = await cadastros(db);
  const pedidos = await ler(db.from('v_pedidos').select('id,numero,cliente').eq('status', 'Aberto').order('numero', { ascending: false }));
  const v = await formModal({ titulo: 'Nova OP de estamparia', texto: 'As peças saem do estoque agora e voltam quando a OP retornar.', botao: 'Criar OP', campos: [
    { k: 'produto', r: 'Produto', tipo: 'select', opcoes: ops(cad.produtos, pre.produto_id), valor: pre.produto_id, req: true },
    { k: 'cor', r: 'Cor', tipo: 'select', opcoes: ops(cad.cores, pre.cor_id), valor: pre.cor_id, req: true },
    { k: 'tam', r: 'Tamanho', tipo: 'select', opcoes: ops(cad.tamanhos, pre.tamanho_id), valor: pre.tamanho_id, req: true },
    { k: 'qtd', r: 'Quantidade', tipo: 'number', min: 1, req: true, valor: pre.qtd },
    { k: 'estampa', r: 'Estampa', req: true },
    { k: 'prev', r: 'Previsão de retorno', tipo: 'date' },
    { k: 'pedido', r: 'Pedido (opcional)', tipo: 'select', opcoes: pedidos.map(p => [p.id, `${p.numero} · ${p.cliente}`]), vazio: 'Sem pedido' },
    { k: 'obs', r: 'Observação' }] });
  if (!v) return;
  if (await chamar(db, 'criar_op_estamparia', { p_produto_id: +v.produto, p_cor_id: +v.cor, p_tamanho_id: +v.tam, p_qtd: v.qtd, p_estampa: v.estampa, p_previsao: v.prev, p_pedido_id: v.pedido, p_obs: v.obs })) {
    toast('OP criada.', 'ok'); depois && depois();
  }
}
