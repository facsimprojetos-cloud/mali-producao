import { db, tem } from '../app.js';
import { h, num, dataHora, chip, chamar, ler, cadastros, toast, formModal, ops, distintos, filtroSel, contem } from '../util.js';

let aba = 'saldo';
let fProd = '', busca = '', zerados = false;

export async function render(el) {
  const pode = tem('estoque');
  el.innerHTML = `
    <div class="cab"><div><h1>Estoque</h1><p>Peças prontas. Entram pela inspeção/retorno e pela estamparia; saem pela expedição e pelas OPs de estamparia.</p></div>
      ${pode ? '<button class="btn acento" id="ajuste">± Ajuste de estoque</button>' : ''}</div>
    <div class="abas"><button data-a="saldo" class="${aba === 'saldo' ? 'ativo' : ''}">Saldo</button><button data-a="mov" class="${aba === 'mov' ? 'ativo' : ''}">Movimentações</button></div>
    <div id="alvo"></div>`;
  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); });
  el.querySelector('#ajuste')?.addEventListener('click', () => ajuste({}, () => render(el)));
  const alvo = el.querySelector('#alvo');

  if (aba === 'mov') {
    const movs = (await ler(db.from('v_estoque_mov').select('*').order('em', { ascending: false }).limit(400))).filter(m => (!fProd || m.produto === fProd) && contem(m, ['produto', 'cor', 'lote', 'obs', 'cliente'], busca));
    alvo.innerHTML = `${filtros(distintos(movs, 'produto'))}
      <div class="tabela-wrap"><table><thead><tr><th>Quando</th><th>Tipo</th><th>Origem</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th>Lote</th><th>Pedido / cliente</th><th>Obs.</th><th>Usuário</th></tr></thead>
      <tbody>${movs.map(m => `<tr><td>${dataHora(m.em)}</td><td>${chip(m.tipo, m.tipo === 'ENTRADA' ? 'ok' : m.tipo === 'SAÍDA' ? 'erro' : 'alerta')}</td><td>${h(m.origem)}</td>
        <td>${h(m.produto)}</td><td>${h(m.cor)}</td><td>${h(m.tamanho)}</td><td class="n forte">${m.tipo === 'SAÍDA' ? '−' : ''}${num(m.qtd)}</td><td>${h(m.lote || '')}</td>
        <td>${h([m.pedido_numero, m.cliente].filter(Boolean).join(' · '))}</td><td class="peq">${h(m.obs || '')}</td><td class="peq">${h(m.usuario || '')}</td></tr>`).join('') || '<tr><td colspan="11" class="vazio">Sem movimentações.</td></tr>'}</tbody></table></div>`;
    ligarFiltros(alvo, el);
    return;
  }

  let q = db.from('v_estoque').select('*').order('produto').order('cor').order('tamanho_ordem');
  if (!zerados) q = q.neq('saldo', 0);
  const lista = await ler(q);
  const filtrada = lista.filter(x => (!fProd || x.produto === fProd) && contem(x, ['produto', 'cor', 'tamanho'], busca));
  const grupos = new Map();
  filtrada.forEach(x => { if (!grupos.has(x.produto)) grupos.set(x.produto, []); grupos.get(x.produto).push(x); });
  alvo.innerHTML = `${filtros(distintos(lista, 'produto'))}
    <label class="peq"><input type="checkbox" id="zer" ${zerados ? 'checked' : ''}> mostrar itens zerados</label>
    <p class="muted peq">${num(filtrada.reduce((a, x) => a + x.saldo, 0))} peças em estoque</p>
    <div class="tabela-wrap"><table><thead><tr><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Entradas</th><th class="n">Saídas</th><th class="n">Ajustes</th><th class="n">Saldo</th><th></th></tr></thead>
    <tbody>${[...grupos.entries()].map(([p, itens]) => `<tr class="grupo"><td colspan="8">${h(p)} · ${num(itens.reduce((a, x) => a + x.saldo, 0))} peças</td></tr>
      ${itens.map(x => `<tr><td>${h(x.produto)}</td><td>${h(x.cor)}</td><td>${h(x.tamanho)}</td><td class="n">${num(x.entradas)}</td><td class="n">${num(x.saidas)}</td><td class="n">${num(x.ajustes)}</td>
        <td class="n forte">${num(x.saldo)}</td><td><div class="acoes">
        ${pode ? `<button class="btn peq" data-aj="${x.produto_id}|${x.cor_id}|${x.tamanho_id}">±</button>` : ''}
        ${x.saldo > 0 && (tem('estamparia') || pode) ? `<button class="btn peq" data-op="${x.produto_id}|${x.cor_id}|${x.tamanho_id}|${x.saldo}">🎨 Estampar</button>` : ''}
        </div></td></tr>`).join('')}`).join('') || '<tr><td colspan="8" class="vazio">Estoque vazio.</td></tr>'}</tbody></table></div>`;
  ligarFiltros(alvo, el);
  alvo.querySelector('#zer').onchange = (e) => { zerados = e.target.checked; render(el); };
  alvo.querySelectorAll('[data-aj]').forEach(b => b.onclick = () => { const [p, c, t] = b.dataset.aj.split('|').map(Number); ajuste({ p, c, t }, () => render(el)); });
  alvo.querySelectorAll('[data-op]').forEach(b => b.onclick = async () => {
    const [p, c, t, s] = b.dataset.op.split('|').map(Number);
    const { novaOp } = await import('./etapas.js');
    novaOp(() => render(el), { produto_id: p, cor_id: c, tamanho_id: t, qtd: s });
  });
}

const filtros = (prods) => `<div class="filtros">${filtroSel('fp', 'Produto', prods, fProd)}<label class="campo">Buscar<input id="fb" value="${h(busca)}" placeholder="Cor, tamanho, lote…"></label></div>`;
function ligarFiltros(alvo, el) {
  alvo.querySelector('#fp').onchange = (e) => { fProd = e.target.value; render(el); };
  alvo.querySelector('#fb').onchange = (e) => { busca = e.target.value; render(el); };
}

async function ajuste(pre, depois) {
  const cad = await cadastros(db);
  const v = await formModal({ titulo: 'Ajuste de estoque', texto: 'Use quantidade positiva para incluir e negativa para retirar (inventário, perda, devolução…).', botao: 'Registrar ajuste', campos: [
    { k: 'p', r: 'Produto', tipo: 'select', opcoes: ops(cad.produtos, pre.p), valor: pre.p, req: true },
    { k: 'c', r: 'Cor', tipo: 'select', opcoes: ops(cad.cores, pre.c), valor: pre.c, req: true },
    { k: 't', r: 'Tamanho', tipo: 'select', opcoes: ops(cad.tamanhos, pre.t), valor: pre.t, req: true },
    { k: 'q', r: 'Quantidade (+/−)', tipo: 'number', step: 1, req: true },
    { k: 'obs', r: 'Motivo', req: true }],
    validar: (v) => !v.q ? 'Informe uma quantidade diferente de zero.' : null });
  if (v && await chamar(db, 'ajustar_estoque', { p_produto_id: +v.p, p_cor_id: +v.c, p_tamanho_id: +v.t, p_qtd: v.q, p_obs: v.obs })) { toast('Ajuste registrado.', 'ok'); depois(); }
}
