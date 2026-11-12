import { db } from './app.js';
import { EMPRESA } from './config.js';
import { h, num, moeda, data, dataHora, ler, imprimirHtml } from './util.js';

// Imprime o romaneio (A4) de uma remessa, com os aviamentos enviados
export async function imprimirRomaneio(remessaId) {
  const [rem] = await ler(db.from('v_remessas').select('*').eq('id', remessaId));
  const itens = await ler(db.from('v_envios').select('*').eq('remessa_id', remessaId).order('lote'));
  if (!rem) return;
  const av = [['Viés', rem.vies], ['Fio', rem.fio], ['Linha', rem.linha], ['Elástico', rem.elastico], ['Alça', rem.alca], ['Etiqueta', rem.etiqueta]].filter(x => x[1] != null);
  const linhas = itens.map(e => `<tr>
    <td>${h(e.lote)}</td><td>${h(e.produto)}</td><td>${h(e.cor)}</td><td>${h(e.tamanho)}</td>
    <td style="text-align:right">${num(e.qtd)}</td><td style="text-align:right">${moeda(e.valor_unit)}</td>
    <td style="text-align:right">${moeda(e.qtd * e.valor_unit)}</td></tr>`).join('');
  imprimirHtml(`<div class="romaneio">
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div><h1>${h(EMPRESA)} — ROMANEIO DE ENVIO Nº ${h(rem.numero)}</h1>
        <div>Facção: <b>${h(rem.faccao)}</b>${rem.telefone ? ` · ${h(rem.telefone)}` : ''}</div>${rem.endereco ? `<div>${h(rem.endereco)}</div>` : ''}</div>
      <div style="text-align:right">Envio: <b>${dataHora(rem.data)}</b><br>Previsão de retorno: <b>${data(rem.previsao)}</b></div>
    </div>
    <table><thead><tr><th>Sublote</th><th>Produto</th><th>Cor</th><th>Tam.</th><th>Qtd</th><th>R$ unit.</th><th>Total</th></tr></thead>
      <tbody>${linhas}</tbody>
      <tfoot><tr><th colspan="4" style="text-align:right">Totais</th><th style="text-align:right">${num(rem.qtd_total)}</th><th></th><th style="text-align:right">${moeda(rem.valor_total)}</th></tr></tfoot>
    </table>
    ${av.length ? `<p><b>Aviamentos enviados:</b> ${av.map(([n, v]) => `${n}: ${num(v, 2)}`).join(' · ')}</p>` : ''}
    ${rem.obs ? `<p>Obs.: ${h(rem.obs)}</p>` : ''}
    <div class="assin"><div>Responsável pelo envio</div><div>Facção (recebido em ___/___/____)</div></div>
  </div>`);
}
