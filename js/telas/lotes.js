import { db, tem } from '../app.js';
import { PREVISAO_DIAS } from '../config.js';
import { h, num, moeda, data, dataHora, chip, modal, chamar, ler, cadastros, opcoes, toast, token, hojeISO, confirmar, contem, formModal } from '../util.js';
import { imprimirRomaneio } from '../romaneio.js';

let aba = 'separar';
let busca = '';
const selecionados = new Map(); // sublote_id -> qtd

export async function render(el) {
  if (aba === 'remessas') return renderRemessas(el);
  const lista = await ler(db.from('v_sublotes').select('*').gt('qtd_saldo', 0).order('criado_em', { ascending: false }).order('tamanho_ordem').order('codigo').limit(800));
  const pode = tem('faccao');
  const filtrada = lista.filter(s => contem(s, ['codigo', 'lote', 'produto', 'cor', 'tamanho', 'pedido_numero'], busca));
  for (const id of selecionados.keys()) if (!lista.some(s => s.id === id)) selecionados.delete(id);
  const grupos = new Map();
  filtrada.forEach(s => { if (!grupos.has(s.lote)) grupos.set(s.lote, []); grupos.get(s.lote).push(s); });
  const ncol = pode ? 9 : 7;

  el.innerHTML = `
    ${cab(pode)}
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Lote, produto, cor, pedido…"></label></div>
    <div class="tabela-wrap"><table>
      <thead><tr>${pode ? '<th></th>' : ''}<th>Sublote</th><th>Produto</th><th>Cor</th><th>Tam.</th><th>Pedido</th><th class="n">Cortado</th><th class="n">A distribuir</th>${pode ? '<th class="n">Enviar</th>' : ''}</tr></thead>
      <tbody>${[...grupos.entries()].map(([lote, itens]) => `
        <tr class="grupo"><td colspan="${ncol}">Lote ${h(lote)} · ${h(itens[0].produto)} · ${num(itens.reduce((a, s) => a + s.qtd_saldo, 0))} peças
          ${pode ? `<button class="btn peq" data-tudo="${h(lote)}" style="margin-left:8px">Selecionar lote</button>` : ''}</td></tr>
        ${itens.map(s => `<tr>
          ${pode ? `<td><input type="checkbox" data-sel="${s.id}" ${selecionados.has(s.id) ? 'checked' : ''}></td>` : ''}
          <td class="forte">${h(s.codigo)}</td><td>${h(s.produto)}</td><td>${h(s.cor)}</td><td>${h(s.tamanho)}</td><td>${s.pedido_numero || ''}</td>
          <td class="n">${num(s.qtd_cortada)}</td><td class="n forte">${num(s.qtd_saldo)}</td>
          ${pode ? `<td class="n"><input class="inp num" type="number" min="1" max="${s.qtd_saldo}" data-qtd="${s.id}" value="${selecionados.get(s.id) ?? s.qtd_saldo}"></td>` : ''}
        </tr>`).join('')}`).join('') || `<tr><td colspan="${ncol}" class="vazio">Nenhum sublote aguardando distribuição.</td></tr>`}
      </tbody></table></div>`;

  ligarAbas(el);
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  const btn = el.querySelector('#enviar');
  const atualizar = () => { if (btn) { btn.disabled = !selecionados.size; btn.textContent = `Enviar para facção (${selecionados.size})`; } };
  el.querySelectorAll('[data-sel]').forEach(cb => cb.onchange = () => {
    const id = cb.dataset.sel, qi = el.querySelector(`[data-qtd="${id}"]`);
    if (cb.checked) selecionados.set(id, +qi.value); else selecionados.delete(id);
    atualizar();
  });
  el.querySelectorAll('[data-tudo]').forEach(b => b.onclick = () => {
    const todos = filtrada.filter(s => s.lote === b.dataset.tudo);
    const marcar = !todos.every(s => selecionados.has(s.id));
    todos.forEach(s => marcar ? selecionados.set(s.id, s.qtd_saldo) : selecionados.delete(s.id));
    render(el);
  });
  el.querySelectorAll('[data-qtd]').forEach(i => i.oninput = () => { if (selecionados.has(i.dataset.qtd)) selecionados.set(i.dataset.qtd, +i.value); });
  btn?.addEventListener('click', () => telaEnvio(lista.filter(s => selecionados.has(s.id)), () => render(el)));
}

function cab(pode) {
  return `<div class="cab"><div><h1>2 - Lotes / Envio</h1><p>Selecione os sublotes cortados e envie para uma facção ou para a produção interna (gera o romaneio).</p></div>
      ${pode && aba === 'separar' ? `<button class="btn acento" id="enviar" ${selecionados.size ? '' : 'disabled'}>Enviar para facção (${selecionados.size})</button>` : ''}</div>
    <div class="abas">
      <button data-a="separar" class="${aba === 'separar' ? 'ativo' : ''}">Aguardando distribuição</button>
      <button data-a="remessas" class="${aba === 'remessas' ? 'ativo' : ''}">Romaneios</button>
    </div>`;
}
function ligarAbas(el) { el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); }); }

async function telaEnvio(itens, depois) {
  const cad = await cadastros(db);
  const previsao = new Date(Date.now() + PREVISAO_DIAS * 86400000).toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  const tk = token();
  const valorProd = (s) => cad.produtos.find(p => p.id === s.produto_id)?.valor_faccao ?? '';
  const corpo = `
    <div class="grade g2">
      <label class="campo">Facção<select id="fac">${opcoes(cad.faccoes.filter(f => f.ativo), null)}</select></label>
      <label class="campo">Previsão de retorno<input type="date" id="prev" value="${previsao}" min="${hojeISO()}"></label>
    </div>
    <div class="tabela-wrap" style="margin-top:12px"><table>
      <thead><tr><th>Sublote</th><th>Produto</th><th>Cor/Tam</th><th class="n">Qtd</th><th class="n">R$ por peça</th><th class="n">Total</th></tr></thead>
      <tbody>${itens.map(s => `<tr data-id="${s.id}">
          <td>${h(s.codigo)}</td><td>${h(s.produto)}</td><td>${h(s.cor)} / ${h(s.tamanho)}</td>
          <td class="n"><input class="inp num" type="number" min="1" max="${s.qtd_saldo}" data-campo="qtd" value="${selecionados.get(s.id) || s.qtd_saldo}"></td>
          <td class="n"><input class="inp num" type="number" min="0" step="0.01" data-campo="v" value="${valorProd(s)}"></td>
          <td class="n" data-total></td></tr>`).join('')}</tbody>
      <tfoot><tr class="grupo"><td colspan="3">Total</td><td class="n" id="tq"></td><td></td><td class="n" id="tv"></td></tr></tfoot></table></div>
    <h3 style="margin-top:12px">Aviamentos enviados (opcional)</h3>
    <div class="grade g3">${['vies:Viés', 'fio:Fio', 'linha:Linha', 'elastico:Elástico', 'alca:Alça', 'etiqueta:Etiqueta'].map(x => { const [k, r] = x.split(':'); return `<label class="campo">${r}<input type="number" min="0" step="any" data-av="${k}"></label>`; }).join('')}</div>
    <label class="campo" style="margin-top:10px">Observação<input id="obs"></label>
    <p class="muted peq" id="aviso-int"></p>`;
  modal({
    titulo: 'Enviar para facção', corpo, largo: true,
    aoAbrir: (m) => {
      const atualizar = () => {
        const fac = cad.faccoes.find(f => f.id === +m.querySelector('#fac').value);
        m.querySelector('#aviso-int').textContent = fac?.interna ? 'Produção interna: o lote também aparece em Produção Interna para apontamento.' : '';
        let tq = 0, tv = 0;
        m.querySelectorAll('tbody tr').forEach(tr => {
          const q = +tr.querySelector('[data-campo=qtd]').value || 0, v = +(tr.querySelector('[data-campo=v]').value || 0);
          tr.querySelector('[data-total]').textContent = moeda(q * v); tq += q; tv += q * v;
        });
        m.querySelector('#tq').textContent = num(tq); m.querySelector('#tv').textContent = moeda(tv);
      };
      m.addEventListener('input', atualizar); m.addEventListener('change', atualizar); atualizar();
    },
    botoes: [{ texto: 'Cancelar' }, {
      texto: 'Confirmar envio', classe: 'pri', acao: async (m) => {
        const fac = +m.querySelector('#fac').value;
        if (!fac) { toast('Selecione a facção.', 'erro'); return false; }
        const lista = [...m.querySelectorAll('tbody tr')].map(tr => ({ sublote_id: tr.dataset.id, qtd: +tr.querySelector('[data-campo=qtd]').value,
          valor_unit: tr.querySelector('[data-campo=v]').value === '' ? null : +tr.querySelector('[data-campo=v]').value }));
        if (lista.some(x => !(x.qtd > 0))) { toast('Quantidade inválida.', 'erro'); return false; }
        const av = {}; m.querySelectorAll('[data-av]').forEach(i => { if (i.value !== '') av[i.dataset.av] = +i.value; });
        const nomeFac = m.querySelector('#fac').selectedOptions[0].textContent;
        if (!await confirmar('Confirmar envio', `Enviar <b>${num(lista.reduce((a, x) => a + x.qtd, 0))}</b> peças para <b>${h(nomeFac)}</b>?`)) return false;
        const r = await chamar(db, 'enviar_faccao', { p_faccao_id: fac, p_itens: lista, p_token: tk, p_previsao: m.querySelector('#prev').value || null, p_aviamentos: av, p_obs: m.querySelector('#obs').value || null });
        if (!r) return false;
        selecionados.clear();
        toast(r.ja_processado ? 'Envio já havia sido registrado.' : `Enviado: ${num(r.qtd_total)} peças (${moeda(r.valor_total)}).`, 'ok');
        depois();
        if (await confirmar('Romaneio', 'Imprimir o romaneio deste envio?', 'Imprimir')) imprimirRomaneio(r.remessa_id);
      }
    }]
  });
}

async function renderRemessas(el) {
  const rems = await ler(db.from('v_remessas').select('*').order('data', { ascending: false }).limit(200));
  const pode = tem('faccao');
  const lista = rems.filter(r => contem(r, ['numero', 'faccao', 'obs'], busca));
  el.innerHTML = `${cab(pode)}
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Nº, facção…"></label></div>
    <div class="tabela-wrap"><table><thead><tr><th>Nº</th><th>Data</th><th>Facção</th><th class="n">Itens</th><th class="n">Peças</th><th class="n">Valor</th><th>Previsão</th><th></th></tr></thead>
    <tbody>${lista.map(r => `<tr><td class="forte">${r.numero}</td><td>${dataHora(r.data)}</td><td>${h(r.faccao)}</td><td class="n">${r.itens}</td><td class="n">${num(r.qtd_total)}</td>
      <td class="n">${moeda(r.valor_total)}</td><td>${data(r.previsao)}</td>
      <td><div class="acoes"><button class="btn peq" data-imp="${r.id}">🖨 Romaneio</button>${pode ? `<button class="btn peq" data-ed="${r.id}">Editar</button>` : ''}</div></td></tr>`).join('')
      || '<tr><td colspan="8" class="vazio">Nenhum romaneio.</td></tr>'}</tbody></table></div>`;
  ligarAbas(el);
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  el.querySelectorAll('[data-imp]').forEach(b => b.onclick = () => imprimirRomaneio(b.dataset.imp));
  el.querySelectorAll('[data-ed]').forEach(b => b.onclick = async () => {
    const r = rems.find(x => x.id === b.dataset.ed);
    const v = await formModal({ titulo: `Romaneio ${r.numero} — ${r.faccao}`, campos: [
      { k: 'previsao', r: 'Previsão de retorno', tipo: 'date', valor: r.previsao },
      { k: 'vies', r: 'Viés', tipo: 'number', valor: r.vies }, { k: 'fio', r: 'Fio', tipo: 'number', valor: r.fio },
      { k: 'linha', r: 'Linha', tipo: 'number', valor: r.linha }, { k: 'elastico', r: 'Elástico', tipo: 'number', valor: r.elastico },
      { k: 'alca', r: 'Alça', tipo: 'number', valor: r.alca }, { k: 'etiqueta', r: 'Etiqueta', tipo: 'number', valor: r.etiqueta },
      { k: 'obs', r: 'Observação', valor: r.obs }] });
    if (!v) return;
    const { previsao, obs, ...av } = v;
    if (await chamar(db, 'editar_remessa', { p_remessa_id: r.id, p_previsao: previsao, p_aviamentos: av, p_obs: obs })) { toast('Romaneio atualizado.', 'ok'); render(el); }
  });
}
