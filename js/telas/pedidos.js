import { db, tem } from '../app.js';
import { h, num, data, chip, modal, chamar, ler, cadastros, opcoes, toast, pedirTexto, hojeISO, contem, confirmar } from '../util.js';

let aba = 'Aberto';
let busca = '';
const COR = { Aberto: 'info', Entregue: 'ok', Cancelado: 'erro' };

export async function render(el) {
  const pode = tem('comercial');
  let q = db.from('v_pedidos').select('*').order('numero', { ascending: false }).limit(300);
  if (aba !== 'todos') q = q.eq('status', aba);
  const pedidos = await ler(q);
  const ids = pedidos.map(p => p.id);
  const itens = ids.length ? await ler(db.from('v_pedido_itens').select('*').in('pedido_id', ids).order('produto').order('tamanho_ordem')) : [];
  const lista = pedidos.filter(p => contem(p, ['numero', 'cliente', 'obs'], busca) || itens.some(i => i.pedido_id === p.id && contem(i, ['produto', 'cor'], busca)));

  el.innerHTML = `
    <div class="cab"><div><h1>Pedidos</h1><p>Pedidos de clientes, com acompanhamento de corte, estoque e entrega por item.</p></div>
      ${pode ? '<button class="btn acento" id="novo">+ Novo pedido</button>' : ''}</div>
    <div class="abas">${['Aberto', 'Entregue', 'Cancelado', 'todos'].map(a => `<button data-a="${a}" class="${aba === a ? 'ativo' : ''}">${a === 'todos' ? 'Todos' : a + 's'}</button>`).join('')}</div>
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Nº, cliente, produto…"></label></div>
    <div class="lista-cards">${lista.map(p => cartao(p, itens.filter(i => i.pedido_id === p.id), pode)).join('') || '<div class="vazio">Nenhum pedido.</div>'}</div>`;

  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); });
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  el.querySelector('#novo')?.addEventListener('click', () => formPedido(null, [], () => render(el)));
  el.querySelectorAll('[data-acao]').forEach(b => b.onclick = async () => {
    const p = pedidos.find(x => x.id === b.dataset.id);
    const its = itens.filter(i => i.pedido_id === p.id);
    if (b.dataset.acao === 'editar') formPedido(p, its, () => render(el));
    if (b.dataset.acao === 'cancelar') {
      const m = await pedirTexto(`Cancelar pedido ${p.numero}`, 'Expedições ainda não liberadas também serão canceladas.', { botao: 'Cancelar pedido' });
      if (m && await chamar(db, 'cancelar_pedido', { p_id: p.id, p_motivo: m })) { toast('Pedido cancelado.', 'ok'); render(el); }
    }
    if (b.dataset.acao === 'reabrir') {
      if (await confirmar('Reabrir pedido', `Reabrir o pedido ${p.numero}?`) && await chamar(db, 'reabrir_pedido', { p_id: p.id })) { toast('Pedido reaberto.', 'ok'); render(el); }
    }
    if (b.dataset.acao === 'corte') {
      const { formCorte } = await import('./corte.js');
      const cad = await cadastros(db);
      const prods = [...new Set(its.map(i => i.produto_id))];
      const prod = prods[0];
      const doProd = its.filter(i => i.produto_id === prod);
      formCorte(cad, {
        produto_id: prod, pedido_id: p.id, destino: 'PRODUÇÃO',
        cores: [...new Map(doProd.map(i => [i.cor_id, { cor_id: i.cor_id }])).values()],
        tamanhos: [...new Map(doProd.map(i => [i.tamanho_id, { tamanho_id: i.tamanho_id }])).values()],
      }, () => { location.hash = '#/corte'; });
      if (prods.length > 1) toast('Este pedido tem mais de um produto: crie um corte para cada um.', 'alerta');
    }
  });
}

function cartao(p, its, pode) {
  return `<div class="item">
    <div class="linha1"><div><div class="tit">Pedido ${p.numero} · ${h(p.cliente)}</div>
      <div class="det">Data ${data(p.data)} · Entrega ${p.entrega ? data(p.entrega) : '—'} ${p.atrasado ? chip('Atrasado', 'erro') : ''}</div></div>
      ${chip(p.status, COR[p.status])}</div>
    <div class="tabela-wrap" style="margin-top:8px"><table><thead><tr><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th class="n">Cortado</th><th class="n">Estoque</th><th class="n">Entregue</th><th>Estampa / Tag</th></tr></thead>
      <tbody>${its.map(i => `<tr><td>${h(i.produto)}</td><td>${h(i.cor)}</td><td>${h(i.tamanho)}</td><td class="n forte">${num(i.qtd)}</td>
        <td class="n">${num(i.qtd_cortada)}</td><td class="n">${num(i.saldo_estoque)}</td>
        <td class="n">${i.qtd_entregue >= i.qtd ? chip(num(i.qtd_entregue), 'ok') : num(i.qtd_entregue)}</td><td class="peq">${h([i.estampa, i.tag].filter(Boolean).join(' · '))}</td></tr>`).join('')}</tbody>
      <tfoot><tr class="grupo"><td colspan="3">Total</td><td class="n">${num(p.qtd_total)}</td><td colspan="2"></td><td class="n">${num(p.qtd_entregue)}</td><td></td></tr></tfoot></table></div>
    ${p.obs ? `<div class="det">Obs.: ${h(p.obs)}</div>` : ''}
    <div class="acoes" style="margin-top:10px">
      ${pode && p.status === 'Aberto' ? `<button class="btn peq" data-acao="editar" data-id="${p.id}">Editar</button>` : ''}
      ${tem('corte') && p.status === 'Aberto' ? `<button class="btn pri peq" data-acao="corte" data-id="${p.id}">✂️ Programar corte</button>` : ''}
      ${pode && p.status === 'Aberto' ? `<button class="btn peq perigo" data-acao="cancelar" data-id="${p.id}">Cancelar</button>` : ''}
      ${tem('supervisor') && p.status !== 'Aberto' ? `<button class="btn peq" data-acao="reabrir" data-id="${p.id}">Reabrir</button>` : ''}
    </div></div>`;
}

function linhaItem(cad, v = {}) {
  const at = (l, id) => l.filter(x => x.ativo || x.id === id);
  return `<tr data-id="${h(v.id || '')}">
    <td><select data-c="produto_id">${opcoes(at(cad.produtos, v.produto_id), v.produto_id)}</select></td>
    <td><select data-c="cor_id">${opcoes(at(cad.cores, v.cor_id), v.cor_id)}</select></td>
    <td><select data-c="tamanho_id">${opcoes(at(cad.tamanhos, v.tamanho_id), v.tamanho_id, 'nome', 'id', '—')}</select></td>
    <td><input class="inp num" type="number" min="1" data-c="qtd" value="${h(v.qtd ?? '')}"></td>
    <td><input class="inp" data-c="estampa" value="${h(v.estampa || '')}" style="width:110px"></td>
    <td><input class="inp" data-c="tag" value="${h(v.tag || '')}" style="width:90px"></td>
    <td>${v.qtd_entregue ? '' : '<button type="button" class="btn peq perigo" data-rm>×</button>'}</td></tr>`;
}

async function formPedido(p, its, depois) {
  const cad = await cadastros(db);
  modal({
    titulo: p ? `Editar pedido ${p.numero}` : 'Novo pedido', largo: true,
    corpo: `<form id="fp" class="grade">
      <div class="grade g3">
        <label class="campo">Cliente<select name="cliente" required>${opcoes(cad.clientes.filter(c => c.ativo || c.id === p?.cliente_id), p?.cliente_id)}</select></label>
        <label class="campo">Data<input type="date" name="data" value="${p?.data || hojeISO()}"></label>
        <label class="campo">Entrega prevista<input type="date" name="entrega" value="${p?.entrega || ''}"></label>
      </div>
      <div class="tabela-wrap"><table><thead><tr><th>Produto</th><th>Cor</th><th>Tam.</th><th>Qtd</th><th>Estampa</th><th>Tag</th><th></th></tr></thead>
        <tbody id="its">${(its.length ? its : [{}]).map(i => linhaItem(cad, i)).join('')}</tbody></table></div>
      <div class="acoes"><button type="button" class="btn peq" id="add">+ Item</button><button type="button" class="btn peq" id="grade">+ Grade (vários tamanhos)</button></div>
      <label class="campo">Observações<input name="obs" value="${h(p?.obs || '')}"></label>
      <div class="ok-box" id="tot"></div></form>`,
    aoAbrir: (m) => {
      const tb = m.querySelector('#its');
      const tot = () => { m.querySelector('#tot').innerHTML = `Total: <b>${num([...tb.querySelectorAll('[data-c=qtd]')].reduce((a, i) => a + (+i.value || 0), 0))}</b> peças`; };
      m.addEventListener('input', tot); tot();
      m.querySelector('#add').onclick = () => {
        const ult = tb.lastElementChild;
        tb.insertAdjacentHTML('beforeend', linhaItem(cad, ult ? { produto_id: +ult.querySelector('[data-c=produto_id]').value, cor_id: +ult.querySelector('[data-c=cor_id]').value } : {}));
      };
      m.querySelector('#grade').onclick = () => {
        const ult = tb.lastElementChild;
        const base = ult ? { produto_id: +ult.querySelector('[data-c=produto_id]').value, cor_id: +ult.querySelector('[data-c=cor_id]').value } : {};
        cad.tamanhos.filter(t => t.ativo).forEach(t => tb.insertAdjacentHTML('beforeend', linhaItem(cad, { ...base, tamanho_id: t.id })));
        if (ult && !ult.querySelector('[data-c=qtd]').value && !ult.dataset.id) ult.remove();
      };
      m.addEventListener('click', (e) => { if (e.target.matches('[data-rm]') && tb.children.length > 1) { e.target.closest('tr').remove(); tot(); } });
    },
    botoes: [{ texto: 'Cancelar' }, { texto: p ? 'Salvar' : 'Criar pedido', classe: 'pri', acao: async (m) => {
      const f = m.querySelector('#fp'); if (!f.reportValidity()) return false;
      const itens = [...m.querySelectorAll('#its tr')].map(tr => {
        const g = (c) => tr.querySelector(`[data-c=${c}]`).value;
        return { id: tr.dataset.id || null, produto_id: +g('produto_id'), cor_id: +g('cor_id'), tamanho_id: +g('tamanho_id'), qtd: +g('qtd'), estampa: g('estampa') || null, tag: g('tag') || null };
      }).filter(i => i.qtd > 0 || i.id);
      if (!itens.length) { toast('Inclua ao menos um item com quantidade.', 'erro'); return false; }
      if (itens.some(i => !i.produto_id || !i.cor_id || !i.tamanho_id || !(i.qtd > 0))) { toast('Preencha produto, cor, tamanho e quantidade de todos os itens.', 'erro'); return false; }
      const r = await chamar(db, 'salvar_pedido', { p_id: p?.id || null, p_cliente_id: +f.cliente.value, p_data: f.data.value || null, p_entrega: f.entrega.value || null, p_obs: f.obs.value || null, p_itens: itens });
      if (!r) return false;
      toast('Pedido salvo.', 'ok'); depois();
    } }]
  });
}
