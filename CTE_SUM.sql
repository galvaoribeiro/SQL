-- 28 minutos
-- EXECUTANDO CTE_VAF - SEM ALTERAÇÕES

with tab_efd as ( -- sumariza o valor total das entradas, no caso de empresas de Rondônia para fazer o rateio proporcional às saídas
    select 
    extract(year from t.da_referencia)||t.co_cnpj_cpf_declarante ano_cnpj,
    extract(year from t.da_referencia) ano , t.co_cnpj_cpf_declarante as cnpj, sum(t.vl_operacao) as soper from BI.fato_efd_sumarizada t 
    left join bi.dm_cfop c on c.co_cfop = t.co_cfop
    where extract (year from t.da_referencia) = '&ANO'
    --and t.co_cnpj_cpf_declarante = '04503660003242' 
    and t.uf_origem = 'RO'
    and c.in_vaf = 'X'
    and c.co_grupo in ('1000', '2000', '3000')
    group by t.co_cnpj_cpf_declarante, extract(year from t.da_referencia), extract(year from t.da_referencia)||t.co_cnpj_cpf_declarante
),

tab_nff as ( -- sumariza o valor total das entradas, no caso de empresas de fora, para fazer o rateio proporcional às saídas
    select 
    extract(year from t.dhemi)||t.co_destinatario ano_cnpj,
    extract(year from t.dhemi) ano, t.co_destinatario as cnpj, sum(t.prod_vprod+t.prod_voutro + t.prod_vfrete + t.prod_vseg - t.prod_vdesc) sprod
    from BI.fato_nfe_detalhe t
    left join bi.dm_cfop c on c.co_cfop = t.co_cfop
    where t.co_uf_emit = 'RO' 
    --and t.co_destinatario = '04503660003242'
    and extract(year from t.dhemi) = (select distinct ano from tab_efd)
    and t.co_emitente <> t.co_destinatario
    and c.co_grupo in ('5000', '6000', '7000')
    and c.in_vaf = 'X'
    and t.co_tp_nf = 1
    and t.co_finnfe in (1,2,3)
    group by t.co_destinatario, extract(year from t.dhemi), extract(year from t.dhemi)||t.co_destinatario
),

tab_bpe as ( -- sumariza o total das saídas de bilhete de passagem eletrônico e depois soma com as saídas de CTe para encontrar as saídas totais


SELECT
extract(year from e.dhemi)||substr(e.chave_acesso,7,14) ano_cnpj,
extract(year from e.dhemi) ano,
substr(e.chave_acesso,7,14) CNPJ,
sum(to_number(replace(z.vpgto,'.',','))) sumbpe
      FROM  BI.bpe_xml e
      left join bi.dm_pessoa p on p.co_cnpj_cpf = substr(e.chave_acesso,7,14)
      left join bi.dm_cnae cnae on cnae.co_cnae = p.co_cnae,
            
             XMLTABLE(XMLNAMESPACES(DEFAULT 'http://www.portalfiscal.inf.br/bpe'),'//infProt' PASSING e.xml
                COLUMNS
                cstat char(3) path 'cStat'  
                ) y ,
                
             XMLTABLE(XMLNAMESPACES(DEFAULT 'http://www.portalfiscal.inf.br/bpe'),'//infValorBPe ' PASSING e.xml
                COLUMNS
                vpgto varchar2(50) path 'vPgto'
                ) z  ,     
                
             XMLTABLE(XMLNAMESPACES(DEFAULT 'http://www.portalfiscal.inf.br/bpe'),'//infBPe' PASSING e.xml
                COLUMNS
                ide_ufini varchar2(2) path 'ide/UFIni',
                ide_uffim varchar2(2) path 'ide/UFFim',
                ide_modal number path 'ide/modal',
                ide_tpbpe number path 'ide/tpBPe',
                ide_cmunini varchar2(7) path 'ide/cMunIni',
                ide_cmunfim varchar2(7) path 'ide/cMunFim'
                
                ) w
               
      where extract(year from e.dhemi) = (select distinct ano from tab_efd)
      and w.ide_ufini = 'RO'
      and w.ide_tpbpe in (0,3) --[Tipos de CT-e existentes: 0 = Normal; 3 = substituição]
      and w.ide_modal in (1,3,4) --Tipos de modal existentes: 01 – Rodoviário; 03 – Aquaviário; 04 – Ferroviário]
      and w.ide_cmunini <> w.ide_cmunfim
      and e.cstat in (100, 150)
      and (cnae.co_divisao in ('49','50','51','52','53') or cnae.co_divisao is null) -- divisões de CNAE de empresas de transporte 
      and (cnae.co_cnae not in ('5211701', '5211702', '5211799') or cnae.co_cnae is null) -- exclui os CNAE que não tem haver com transporte
      --and substr(e.chave_acesso,7,14) = '045036600032421'
      
      group by extract(year from e.dhemi), substr(e.chave_acesso,7,14), extract(year from e.dhemi)||substr(e.chave_acesso,7,14)
             
        ),

tab_cte as (

SELECT extract(year from t.dhemi)||t.emit_co_cnpj ano_cnpj, t.chave_acesso, extract(year from t.dhemi) ano, t.dhemi, t.infprot_cstat cstat, t.co_mod,
t.co_ufini as uf_inicio, t.co_uffim as uf_fim, substr(t.co_munini,1,6) as cod_munini, t.xmunini as municipio_inicio, substr(t.co_munfim,1,6) as cod_munfim, t.xmunfim as municipio_fim,
t.co_tpcte, t.co_tpserv, t.co_modal, t.emit_co_mun,
t.emit_co_cnpj as cnpj_emitente, t.emit_xnome as nome_emitente, t.emit_mun as municipio_emitente,
case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_CNPJ_CPF) else (
case when t.co_tomador3 = 0 then t.rem_cnpj_cpf -- 0-Remetente;
    when t.co_tomador3 = 1 then t.exp_co_cnpj_cpf -- 1-Expedidor;
    when t.co_tomador3 = 2 then t.receb_cnpj_cpf -- 2-Recebedor;
    when t.co_tomador3 = 3 then t.dest_cnpj_cpf -- 3-Destinatário
    end
) end as cnpj_tomador,

case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_NOME) else (
case when t.co_tomador3 = 0 then t.rem_xnome
    when t.co_tomador3 = 1 then t.exp_xnome
    when t.co_tomador3 = 2 then t.receb_xnome
    when t.co_tomador3 = 3 then t.dest_xnome
    end
) end as nome_tomador,

case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_XMUN) else (
case when t.co_tomador3 = 0 then t.rem_xmun
    when t.co_tomador3 = 1 then t.exp_mun
    when t.co_tomador3 = 2 then t.receb_xmun
    when t.co_tomador3 = 3 then t.dest_xmun
    end
) end as municipio_tomador,

t.co_cfop as cfop, 
t.prest_vtprest as valor_prestacao,
sum(t.prest_vtprest) over (partition by t.emit_co_cnpj, extract(year from t.dhemi)) as sumcte,

t.icms_cst,
t.rem_cnpj_cpf as cnpj_cpf_remetente, t.rem_xnome as nome_remetente,
t.dest_cnpj_cpf as cnpj_cpf_destinatario, t.dest_xnome as nome_destinatario,
t.exp_co_cnpj_cpf as cnpj_cpf_expedidor , 
t.receb_cnpj_cpf as cnpj_cpf_recebedor 
FROM BI.fato_cte_detalhe T 
left join bi.dm_pessoa p on p.co_cnpj_cpf = t.emit_co_cnpj
left join bi.dm_cfop c on c.co_cfop = t.co_cfop
left join bi.dm_cnae cnae on cnae.co_cnae = p.co_cnae
WHERE extract(year from t.dhemi) = (select distinct ano from tab_efd)

and (cnae.co_divisao in ('49','50','51','52','53') or cnae.co_divisao is null) -- divisões de CNAE de empresas de transporte 
and (cnae.co_cnae not in ('5211701', '5211702', '5211799') or cnae.co_cnae is null) -- exclui os CNAE que não tem haver com transporte
--AND t.emit_co_cnpj = '04503660003242'
and t.co_ufini = 'RO' -- o CTe deve ter origem em RO
and t.co_tpcte in (0,1,3) --[Tipos de CT-e existentes: 0 = Normal; 1 = complemento de valor; 2 = Anulação; 3 = substituição]
and t.co_modal in (1,2,3,4,5) --Tipos de modal existentes: 01 – Rodoviário; 02 – Aéreo; 03 – Aquaviário; 04 – Ferroviário; 05 – Dutoviário; 06 – Multimodal ]
and (c.in_vaf = 'X' or c.co_cfop in ('5932','6932'))
--and c.in_vaf = 'X' -- somente os CTe com CFOP de VAF
and t.co_munini <> t.co_munfim -- município de origem deve ser diferente do município de destino (intermunicipal ou interestadual)
and t.infprot_cstat in (100,150) -- 100 autorizada 150 autorizada fora do prazo
and t.co_mod = 57 -- co_mod = 57 CT-e ; co_mod = 67 CT-e outros serviços
and t.co_tpserv in (0,4) --[Tipos de serviço existentes: 0 (normal), 1 (subcontratação), 2 (redespacho), 3 (redespacho intermediário), 4 (serviço vinculado a multimodal), 6 (Transporte de Pessoas), 7 (Transporte de Valores) e 8 (Excesso de Bagagem) ]

UNION ALL

SELECT extract(year from t.dhemi)||t.emit_co_cnpj ano_cnpj, t.chave_acesso, extract(year from t.dhemi) ano, t.dhemi, t.infprot_cstat cstat, t.co_mod,
t.co_ufini as uf_inicio, t.co_uffim as uf_fim, substr(t.co_munini,1,6) as cod_munini, t.xmunini as municipio_inicio, substr(t.co_munfim,1,6) as cod_munfim, t.xmunfim as municipio_fim,
t.co_tpcte, t.co_tpserv, t.co_modal,  t.emit_co_mun,
t.emit_co_cnpj as cnpj_emitente, t.emit_xnome as nome_emitente, t.emit_mun as municipio_emitente,
case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_CNPJ_CPF) else (
case when t.co_tomador3 = 0 then t.rem_cnpj_cpf -- 0-Remetente;
    when t.co_tomador3 = 1 then t.exp_co_cnpj_cpf -- 1-Expedidor;
    when t.co_tomador3 = 2 then t.receb_cnpj_cpf -- 2-Recebedor;
    when t.co_tomador3 = 3 then t.dest_cnpj_cpf -- 3-Destinatário
    end
) end as cnpj_tomador,

case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_NOME) else (
case when t.co_tomador3 = 0 then t.rem_xnome
    when t.co_tomador3 = 1 then t.exp_xnome
    when t.co_tomador3 = 2 then t.receb_xnome
    when t.co_tomador3 = 3 then t.dest_xnome
    end
) end as nome_tomador,

case when t.co_tomador4 = 4 then (t.CO_TOMADOR4_XMUN) else (
case when t.co_tomador3 = 0 then t.rem_xmun
    when t.co_tomador3 = 1 then t.exp_mun
    when t.co_tomador3 = 2 then t.receb_xmun
    when t.co_tomador3 = 3 then t.dest_xmun
    end
) end as municipio_tomador,

t.co_cfop as cfop,
t.prest_vtprest as valor_prestacao,
sum(t.prest_vtprest) over (partition by t.emit_co_cnpj, extract(year from t.dhemi)) as sumcte,


t.icms_cst,
t.rem_cnpj_cpf as cnpj_cpf_remetente, t.rem_xnome as nome_remetente,
t.dest_cnpj_cpf as cnpj_cpf_destinatario, t.dest_xnome as nome_destinatario,
t.exp_co_cnpj_cpf as cnpj_cpf_expedidor ,
t.receb_cnpj_cpf as cnpj_cpf_recebedor 
FROM BI.fato_cte_detalhe T 
left join bi.dm_pessoa p on p.co_cnpj_cpf = t.emit_co_cnpj
left join bi.dm_cfop c on c.co_cfop = t.co_cfop
left join bi.dm_cnae cnae on cnae.co_cnae = p.co_cnae
WHERE extract(year from t.dhemi) = (select distinct ano from tab_efd)

and (cnae.co_divisao in ('49','50','51','52','53') or cnae.co_divisao is null) -- divisões de CNAE de empresas de transporte 
and (cnae.co_cnae not in ('5211701', '5211702', '5211799') or cnae.co_cnae is null) -- exclui os CNAE que não tem haver com transporte
--AND t.emit_co_cnpj = '04503660003242'
and t.co_ufini = 'RO' -- o CTe deve ter origem em RO
and t.co_tpcte in (0,1,3) --[Tipos de CT-e existentes: 0 = Normal; 1 = complemento de valor; 2 = Anulação; 3 = substituição]
and t.co_modal in (1,2,3,4,5) --Tipos de modal existentes: 01 – Rodoviário; 02 – Aéreo; 03 – Aquaviário; 04 – Ferroviário; 05 – Dutoviário; 06 – Multimodal ]
and (c.in_vaf = 'X' or c.co_cfop in ('5932','6932'))
--and c.in_vaf = 'X' -- somente os CTe com CFOP de VAF
and t.co_munini <> t.co_munfim -- município de origem deve ser diferente do município de destino (intermunicipal ou interestadual)
and t.infprot_cstat in (100,150) -- 100 autorizada 150 autorizada fora do prazo
and t.co_mod = 67 -- co_mod = 57 CT-e ; co_mod = 67 CT-e outros serviços
and t.co_tpserv in (6,7,8) --[Tipos de serviço existentes: 0 (normal), 1 (subcontratação), 2 (redespacho), 3 (redespacho intermediário), 4 (serviço vinculado a multimodal), 6 (Transporte de Pessoas), 7 (Transporte de Valores) e 8 (Excesso de Bagagem) ]

)

select extract(year from j.dhemi) ano, j.uf_inicio, 
--j.uf_fim, 
j.cod_munini, l.no_municipio, 
--j.cod_munfim, 
j.cnpj_emitente, p.co_municipio, p.no_razao_social, p.co_regime_pagto, sum(j.valor_liquido) valor

from (

select 
x.chave_acesso, 
x.dhemi, 
x.cstat, 
x.co_mod,
x.uf_inicio,
x.uf_fim, 
x.cod_munini,
x.municipio_inicio, 
x.cod_munfim, 
x.municipio_fim, 
x.co_tpcte, 
x.co_tpserv, 
x.co_modal, 
x.cnpj_emitente, 
x.nome_emitente, 
x.municipio_emitente,
x.cnpj_tomador,
x.nome_tomador, 
x.municipio_tomador,
x.icms_cst, 
x.cfop,
x.valor_prestacao,
-- o select abaixo faz a divisão do valor da saída no CTe (por chave de acesso) pelo total de saídas (CTe/BPe), depois multiplica pelo total das entradas em EFD (RO) ou soma de NFe (Fora de RO), econtrando o rateio das entradas.
-- caso o município do emitente comece por 11 (RO) utilizamos os dados da EFD, senão utilizamos os dados das compras informadas em notas fiscais.
case when x.emit_co_mun like '11%' then (nvl(round((z.soper)*x.valor_prestacao/(NULLIF(nvl(x.sumcte,0),0)+NULLIF(nvl(y.sumbpe,0),0)),2),0))
                                    else (nvl(round((w.sprod)*x.valor_prestacao/(NULLIF(nvl(x.sumcte,0),0)+NULLIF(nvl(y.sumbpe,0),0)),2),0)) end as rateio_entrada,

x.valor_prestacao -
case when x.emit_co_mun like '11%' then (nvl(round((z.soper)*x.valor_prestacao/(NULLIF(nvl(x.sumcte,0),0)+NULLIF(nvl(y.sumbpe,0),0)),2),0))
                                    else (nvl(round((w.sprod)*x.valor_prestacao/(NULLIF(nvl(x.sumcte,0),0)+NULLIF(nvl(y.sumbpe,0),0)),2),0)) end as valor_liquido,
                                    
                                    

x.cnpj_cpf_remetente, 
x.nome_remetente, 
x.cnpj_cpf_destinatario, 
x.nome_destinatario, 
x.cnpj_cpf_expedidor, 
x.cnpj_cpf_recebedor 

from tab_cte x 
left join tab_bpe y on y.ano_cnpj = x.ano_cnpj  
left join tab_efd z on z.ano_cnpj = x.ano_cnpj
left join tab_nff w on w.ano_cnpj = x.ano_cnpj


    ) j LEFT JOIN BI.DM_LOCALIDADE L on l.co_municipio = j.cod_munini
        left join bi.dm_pessoa p on p.co_cnpj_cpf = j.cnpj_emitente
    
    group by
    
    
    extract(year from j.dhemi), 
    j.uf_inicio,    
    --j.uf_fim, 
    j.cod_munini, 
    l.no_municipio, 
    --j.cod_munfim, 
    j.cnpj_emitente, 
    p.no_razao_social,
    p.co_regime_pagto, 
    p.co_municipio
