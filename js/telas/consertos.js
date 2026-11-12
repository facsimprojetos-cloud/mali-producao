import { db, tem } from '../app.js';
import { h, num, moeda, data, chip, modal, chamar, ler, toast, confirmar, contem, DESTINOS } from '../util.js';
import { destinoPadrao } from './faccao.js';

let aba = 'pendentes';
let busca = '';

export async function render(el) {
  const pode = tem('faccao'), sup = tem('supervisor');
  let q = db.from('v_consertos').select('*').order('enviado_em', { ascending: false }).limit(500);
  q = aba === 'pendentes' ? q.is('recebido_em', null) : q.not('recebido_em', 'is', null);
  const lista = (await ler(q)).filter(c => contem(c, ['sublote', 'produto', 'cor', 'faccao'], busca));
  const grupos = new Map();
  lista.forEach(c => { if (!grupos.has(c.faccao)) grupos.set(c.faccao, []); grupos.get(c.faccao).push(c); });
  el.innerHTML = `
    <div class="cab"><div><h1>Consertos</h1><p>Peças com defeito devolvidas à facção (no retorno ou na inspeção). Conserto de retorno é pago quando volta consertado.</p></div></div>
    <div class="abas">
      <button data-a="pendentes" class="${aba === 'pendentes' ? 'ativo' : ''}">Em conserto</button>
      <button data-a="recebidos" class="${aba === 'recebidos' ? 'ativo' : ''}">Recebidos</button>
    </div>
    <div class="filtros"><label class="campo">Buscar<input id="busca" value="${h(busca)}" placeholder="Sublote, produto, facção…"></label></div>
    <div class="tabela-wrap"><table>
      <thead><tr><th>Enviado</th><th>Sublote</th><th>Produto</th><th>Cor</th><th>Tam.</th><th class="n">Qtd</th><th>Origem</th><th class="n">R$ peça</th><th>Obs.</th><th></th></tr></thead>
      <tbody>${[...grupos.entries()].map(([fac, itens]) => `
        <tr class="grupo"><td colspan="10">${h(fac)} · ${num(itens.reduce((a, c) => a + c.qtd, 0))} peça(s)</td></tr>
        ${itens.map(c => `<tr><td>${data(c.enviado_em)}</td><td class="forte">${h(c.sublote)}</td><td>${h(c.produto)}</td><td>${h(c.cor)}</td><td>${h(c.tamanho)}</td>
          <td class="n forte">${num(c.qtd)}${c.recebido_em ? ` <span class="muted peq">(${num(c.qtd_recebida)} ok${c.qtd_perda ? `, ${c.qtd_perda} perda` : ''})</span>` : ''}</td>
          <td>${chip(c.origem === 'RETORNO' ? 'Retorno' : 'Inspeção/etapa')}</td><td class="n">${c.valor_unit > 0 ? moeda(c.valor_unit) : '—'}</td><td class="peq">${h(c.obs || '')}</td>
          <td>${aba === 'pendentes' ? (pode ? `<button class="btn pri peq" data-rec="${c.id}">Recebido</button>` : '')
              : `${data(c.recebido_em)} ${c.pago ? chip('Pago', 'ok') : ''} ${sup && !c.pago ? `<button class="btn peq" data-desf="${c.id}">Desfazer</button>` : ''}`}</td></tr>`).join('')}`).join('')
        || '<tr><td colspan="10" class="vazio">Nenhum conserto.</td></tr>'}</tbody></table></div>`;
  el.querySelectorAll('[data-a]').forEach(b => b.onclick = () => { aba = b.dataset.a; render(el); });
  el.querySelector('#busca').onchange = (e) => { busca = e.target.value; render(el); };
  el.querySelectorAll('[data-desf]').forEach(b => b.onclick = async () => {
    if (!await confirmar('Desfazer recebimento', 'O conserto volta para "Em conserto" (só se a etapa seguinte ainda não começou).', 'Desfazer')) return;
    if (await chamar(db, 'desfazer_recebimento_conserto', { p_conserto_id: b.dataset.desf })) { toast('Recebimento desfeito.', 'ok'); render(el); }
  });
  el.querySelectorAll('[data-rec]').forEach(b => b.onclick = async () => {
    const c = lista.find(x => x.id === b.dataset.rec);
    const { data: prod } = await db.from('produtos').select('estamparia_apos').eq('id', c.produto_id).single();
    modal({
      titulo: 'Conserto recebido',
      corpo: `<p><b>${num(c.qtd)}</b> peça(s) de <b>${h(c.produto)}</b> ${h(c.cor)} ${h(c.tamanho)} — ${h(c.faccao)}</p>
        <form id="fc" class="grade g3">
          <label class="campo">Consertadas<input type="number" name="ok" min="0" max="${c.qtd}" value="${c.qtd}"></label>
          <label class="campo">Perdidas<input type="number" name="perda" min="0" max="${c.qtd}" value="0"></label>
          <label class="campo">Próximo processo<select name="prox">${Object.entries(DESTINOS).map(([k, r]) => `<option value="${k}" ${k === (c.origem === 'RETORNO' ? destinoPadrao(prod) : 'INSPEÇÃO') ? 'selected' : ''}>${r}</option>`).join('')}</select></label>
        </form>`,
      botoes: [{ texto: 'Cancelar' }, { texto: 'Confirmar recebimento', classe: 'pri', acao: async (m) => {
        const f = m.querySelector('#fc'), ok = +f.ok.value || 0, perda = +f.perda.value || 0;
        if (ok + perda !== c.qtd) { toast(`Consertadas + perdidas deve ser ${c.qtd}.`, 'erro'); return false; }
        if (!await chamar(db, 'receber_conserto', { p_conserto_id: c.id, p_qtd: ok, p_perda: perda, p_proximo: f.prox.value })) return false;
        toast('Conserto recebido.', 'ok'); render(el);
      } }]
    });
  });
}
