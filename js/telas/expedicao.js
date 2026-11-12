import { db, tem } from '../app.js';
import { h, num, data, dataHora, chip, chamar, ler, cadastros, toast, formModal, ops, pedirTexto, confirmar, contem } from '../util.js';

let aba = 'atender';
let busca = '';
const COR = { 'Aguardando embalagem': 'info', 'Embalando': 'alerta', 'Embalada': 'ok', 'Liberada': 'ok', 'Cancelada': 'erro' };

export async function render(el) {
  const pode = tem('estoque'), sup = tem('supervisor');
  el.innerHTML = `
    <div class="cab"><div><h1>Expedição</h1><p>Separe os itens dos pedidos a partir do estoque, embale e libere (dá baixa no estoque e marca o pedido como entregue).</p></div>
      ${pode ? '<button class="btn acento" id="avulsa">+ Expedição avulsa</button>' : ''}</div>
    <div class="abas">
      <button data-a="atender" class="${aba === 'atender' ? 'ativo' : ''}">Pedidos a atender</button>
      <button data-a="andamento" class="${aba === 'andamento' ? 'ativo' : ''}">Em andamento</button>
      <button data-a="liberadas" class="${aba === 'liberadas' ? 'ativo' : ''}">Liberadas</button>
    </div>
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Pedido, cliente, produto…"></label></div>
    <div id="alvo"></div>`;
  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); });
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  el.querySelector('#avulsa')?.addEventListener('click', () => avulsa(() => render(el)));
  const alvo = el.querySelector('#alvo');

  if (aba === 'atender') {
    const itens = (await ler(db.from('v_pedido_itens').select('*').eq('pedido_status', 'Aberto').order('entrega').order('pedido_numero').order('produto').order('tamanho_ordem')))
      .filter(i => i.pendente - i.em_expedicao > 0 && contem(i, ['pedido_numero', 'cliente', 'produto', 'cor'], busca));
    const grupos = new Map();
    itens.forEach(i => { const k = `${i.pedido_numero} · ${i.cliente}`; if (!grupos.has(k)) grupos.set(k, []); grupos.get(k).push(i); });
    alvo.innerHTML = `<div class="tabela-wrap"><table><thead><tr><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Pedido</th><th class="n">Entregue</th><th class="n">Em expedição</th><th class="n">Falta</th><th class="n">Em estoque</th><th></th></tr></thead>
      <tbody>${[...grupos.entries()].map(([k, its]) => `<tr class="grupo"><td colspan="9">Pedido ${h(k)} · entrega ${its[0].entrega ? data(its[0].entrega) : '—'}</td></tr>
        ${its.map(i => { const falta = i.pendente - i.em_expedicao; return `<tr><td>${h(i.produto)}</td><td>${h(i.cor)}</td><td>${h(i.tamanho)}</td><td class="n">${num(i.qtd)}</td><td class="n">${num(i.qtd_entregue)}</td>
          <td class="n">${num(i.em_expedicao)}</td><td class="n forte">${num(falta)}</td><td class="n">${i.saldo_estoque >= falta ? chip(num(i.saldo_estoque), 'ok') : chip(num(i.saldo_estoque), i.saldo_estoque > 0 ? 'alerta' : 'erro')}</td>
          <td>${pode && i.saldo_estoque > 0 ? `<button class="btn pri peq" data-sep="${i.id}">Separar</button>` : ''}</td></tr>`; }).join('')}`).join('') || '<tr><td colspan="9" class="vazio">Nenhum item pendente.</td></tr>'}</tbody></table></div>`;
    alvo.querySelectorAll('[data-sep]').forEach(b => b.onclick = async () => {
      const i = itens.find(x => x.id === b.dataset.sep), falta = i.pendente - i.em_expedicao, sug = Math.min(falta, i.saldo_estoque);
      const v = await formModal({ titulo: `Separar — pedido ${i.pedido_numero}`, texto: `${h(i.produto)} ${h(i.cor)} ${h(i.tamanho)} · falta ${falta} · estoque ${i.saldo_estoque}`, botao: 'Separar',
        campos: [{ k: 'q', r: 'Quantidade', tipo: 'number', min: 1, max: falta, valor: sug, req: true }, { k: 'obs', r: 'Observação' }] });
      if (v && await chamar(db, 'criar_expedicao', { p_qtd: v.q, p_pedido_item_id: i.id, p_obs: v.obs })) { toast('Separado para expedição.', 'ok'); render(el); }
    });
    return;
  }

  let q = db.from('v_expedicoes').select('*').limit(400);
  q = aba === 'andamento' ? q.is('liberado_em', null).is('cancelado_em', null).order('criado_em') : q.not('liberado_em', 'is', null).order('liberado_em', { ascending: false });
  const lista = (await ler(q)).filter(x => contem(x, ['numero', 'pedido_numero', 'cliente', 'produto', 'cor'], busca));
  alvo.innerHTML = `<div class="tabela-wrap"><table><thead><tr><th>Nº</th><th>Criada</th><th>Pedido</th><th>Cliente</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th>Status</th>${aba === 'liberadas' ? '<th>Liberada</th>' : '<th class="n">Estoque</th>'}<th></th></tr></thead>
    <tbody>${lista.map(x => `<tr><td class="forte">${x.numero}</td><td>${dataHora(x.criado_em)}</td><td>${x.pedido_numero || '—'}</td><td>${h(x.cliente || '')}</td><td>${h(x.produto)}</td><td>${h(x.cor)}</td><td>${h(x.tamanho)}</td>
      <td class="n forte">${num(x.qtd)}</td><td>${chip(x.status, COR[x.status])}</td>
      ${aba === 'liberadas' ? `<td>${dataHora(x.liberado_em)}</td>` : `<td class="n">${x.saldo_estoque >= x.qtd ? num(x.saldo_estoque) : chip(num(x.saldo_estoque), 'erro')}</td>`}
      <td><div class="acoes">
        ${pode && aba === 'andamento' && !x.embalagem_inicio ? `<button class="btn peq" data-emb="${x.id}|iniciar">▶ Embalar</button>` : ''}
        ${pode && aba === 'andamento' && x.embalagem_inicio && !x.embalagem_fim ? `<button class="btn peq" data-emb="${x.id}|finalizar">✔ Embalado</button>` : ''}
        ${pode && aba === 'andamento' ? `<button class="btn pri peq" data-lib="${x.id}">🚚 Liberar</button><button class="btn peq perigo" data-canc="${x.id}">Cancelar</button>` : ''}
        ${sup && aba === 'liberadas' ? `<button class="btn peq perigo" data-canc="${x.id}">↩ Estornar</button>` : ''}
      </div></td></tr>`).join('') || '<tr><td colspan="11" class="vazio">Nada por aqui.</td></tr>'}</tbody></table></div>`;
  alvo.querySelectorAll('[data-emb]').forEach(b => b.onclick = async () => {
    const [id, ac] = b.dataset.emb.split('|');
    if (await chamar(db, 'embalagem', { p_expedicao_id: id, p_acao: ac })) render(el);
  });
  alvo.querySelectorAll('[data-lib]').forEach(b => b.onclick = async () => {
    const x = lista.find(y => y.id === b.dataset.lib);
    if (!await confirmar('Liberar expedição', `Dar baixa de <b>${x.qtd}</b> ${h(x.produto)} ${h(x.cor)} ${h(x.tamanho)} do estoque${x.pedido_numero ? ` e marcar como entregue no pedido ${x.pedido_numero}` : ''}?`, 'Liberar')) return;
    if (await chamar(db, 'liberar_expedicao', { p_expedicao_id: x.id })) { toast('Expedição liberada.', 'ok'); render(el); }
  });
  alvo.querySelectorAll('[data-canc]').forEach(b => b.onclick = async () => {
    const x = lista.find(y => y.id === b.dataset.canc);
    const m = await pedirTexto(x.liberado_em ? 'Estornar expedição' : 'Cancelar expedição', x.liberado_em ? 'As peças voltam ao estoque e a entrega do pedido é desfeita.' : 'A separação será cancelada.', { botao: 'Confirmar' });
    if (m && await chamar(db, 'cancelar_expedicao', { p_expedicao_id: x.id, p_motivo: m })) { toast('Feito.', 'ok'); render(el); }
  });
}

async function avulsa(depois) {
  const cad = await cadastros(db);
  const v = await formModal({ titulo: 'Expedição avulsa (sem pedido)', botao: 'Criar', campos: [
    { k: 'p', r: 'Produto', tipo: 'select', opcoes: ops(cad.produtos), req: true }, { k: 'c', r: 'Cor', tipo: 'select', opcoes: ops(cad.cores), req: true },
    { k: 't', r: 'Tamanho', tipo: 'select', opcoes: ops(cad.tamanhos), req: true }, { k: 'q', r: 'Quantidade', tipo: 'number', min: 1, req: true },
    { k: 'cli', r: 'Cliente (opcional)', tipo: 'select', opcoes: ops(cad.clientes), vazio: 'Sem cliente' }, { k: 'obs', r: 'Observação' }] });
  if (v && await chamar(db, 'criar_expedicao', { p_qtd: v.q, p_produto_id: +v.p, p_cor_id: +v.c, p_tamanho_id: +v.t, p_cliente_id: v.cli ? +v.cli : null, p_obs: v.obs })) { toast('Expedição criada.', 'ok'); depois(); }
}
