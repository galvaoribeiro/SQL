-- 58 minutos
with tab_efd as ( -- sumariza o valor total das entradas, no caso de empresas de Rondônia para fazer o rateio proporcional às saídas
    select 
    extract(year from t.da_referencia)||t.co_cnpj_cpf_declarante ano_cnpj,
    extract(year from t.da_referencia) ano , t.co_cnpj_cpf_declarante as cnpj, sum(t.vl_operacao) as soper from BI.fato_efd_sumarizada t 
    left join bi.dm_cfop c on c.co_cfop = t.co_cfop
    where extract(year from t.da_referencia) = '&ANO'
    --and t.co_cnpj_cpf_declarante = '01557408000121' 
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
    --and t.co_destinatario = '01557408000121'
    and extract(year from t.dhemi) = (select distinct ano from tab_efd)
    and t.co_emitente <> t.co_destinatario
    and c.co_grupo in ('5000', '6000', '7000')
    and c.in_vaf = 'X'
    and t.co_tp_nf = 1
    and t.co_finnfe in (1,2,3)
    group by t.co_destinatario, extract(year from t.dhemi), extract(year from t.dhemi)||t.co_destinatario
),

tab_cte as ( -- sumariza o total das saídas de conhecimento de transporte eletrônico e depois soma com as saídas de BPe para encontrar as saídas totais


    select extract(year from t.dhemi)||t.emit_co_cnpj ano_cnpj, extract(year from t.dhemi) ano, t.emit_co_cnpj as cnpj, sum(t.prest_vtprest) sumcte from 
    BI.fato_cte_detalhe t
    left join bi.dm_pessoa p on p.co_cnpj_cpf = t.emit_co_cnpj
    left join bi.dm_cfop c on c.co_cfop = t.co_cfop
    left join bi.dm_cnae cnae on cnae.co_cnae = p.co_cnae
    where extract(year from t.dhemi) = (select distinct ano from tab_efd)
    --and t.emit_co_cnpj  = '01557408000121'
    and (cnae.co_divisao in ('49','50','51','52','53') or cnae.co_divisao is null) -- divisões de CNAE de empresas de transporte 
    and (cnae.co_cnae not in ('5211701', '5211702', '5211799') or cnae.co_cnae is null) -- exclui os CNAE que não tem haver com transporte
    and (c.in_vaf = 'X' or c.co_cfop in ('5932','6932'))
    --and c.in_vaf = 'X'
    and t.co_ufini = 'RO'
    and t.co_tpcte in (0,1,3) --[Tipos de CT-e existentes: 0 = Normal; 1 = complemento de valor; 2 = Anulação; 3 = substituição]
    and t.co_modal in (1,2,3,4,5) --Tipos de modal existentes: 01 – Rodoviário; 02 – Aéreo; 03 – Aquaviário; 04 – Ferroviário; 05 – Dutoviário; 06 – Multimodal ]
    and t.co_munini <> t.co_munfim
    and t.infprot_cstat in (100,150)
    group by t.emit_co_cnpj, extract(year from t.dhemi), extract(year from t.dhemi)||t.emit_co_cnpj 
),

tab_bpe as (


SELECT extract(year from t.dhemi)||t.emit_cnpj ano_cnpj , t.chave_acesso, extract(year from t.dhemi) ano, t.dhemi, t.cstat, t.ide_mod,
t.ide_ufini as uf_inicio, t.ide_uffim as uf_fim, substr(t.ide_cmunini,1,6) as cod_munini, substr(t.ide_cmunfim,1,6) as cod_munfim,
t.ide_tpbpe, t.infbpesub_chbpe, t.infbpesub_tpsub, 
t.ide_modal, t.enderemit_cmun,
t.emit_cnpj as cnpj, t.emit_xnome as nome_emitente, t.enderemit_xmun as municipio_emitente,
t.comp_cpf, t.comp_cnpj, t.comp_xnome, t.infpassageiro_cpf, t.infpassageiro_xnome,


t.infvalorbpe_vbp as valor_bilhete,
t.infvalorbpe_vDesconto,
t.infvalorbpe_vPgto pago,
sum(t.infvalorbpe_vPgto) over (partition by t.emit_cnpj, extract(year from t.dhemi)) as sumbpe,   
t.icms_cst

FROM BI.bpe_f_documento T 
left join bi.dm_pessoa p on p.co_cnpj_cpf = t.emit_cnpj
left join bi.dm_cnae cnae on cnae.co_cnae = p.co_cnae
WHERE extract(year from t.dhemi) = (select distinct ano from tab_efd)
and (cnae.co_divisao in ('49','50','51','52','53') or cnae.co_divisao is null) -- divisões de CNAE de empresas de transporte 
and (cnae.co_cnae not in ('5211701', '5211702', '5211799') or cnae.co_cnae is null) -- exclui os CNAE que não tem haver com transporte


--and t.emit_cnpj = '01557408000121'
and t.ide_ufini = 'RO' -- o BPe deve ter origem em RO
and t.ide_tpbpe in (0,3) --[Tipos de CT-e existentes: 0 = Normal; 3 = substituição]
and t.ide_modal in (1,3,4) --Tipos de modal existentes: 01 – Rodoviário; 03 – Aquaviário; 04 – Ferroviário]
and t.ide_cmunini <> t.ide_cmunfim -- município de origem deve ser diferente do município de destino (intermunicipal ou interestadual)
and t.cstat in (100, 150) -- 100 autorizada 150 autorizada fora do prazo

        )
        
        select extract(year from j.dhemi) ano, j.uf_inicio, 
        --j.uf_fim, 
        j.cod_munini, l.no_municipio, 
        --j.cod_munfim, 
        j.cnpj, p.no_razao_social, p.co_municipio, p.co_regime_pagto, sum(valor_liquido) valor from (
        
        select
        y.chave_acesso, 
        y.dhemi, 
        y.cstat, 
        y.ide_mod,
        y.uf_inicio, 
        y.uf_fim, 
        y.cod_munini, 
        y.cod_munfim,
        y.ide_tpbpe, 
        y.ide_modal,
        y.cnpj, 
        y.nome_emitente, 
        y.municipio_emitente, 
        y.infpassageiro_cpf as cpf_passageiro, 
        y.infpassageiro_xnome as nome_passageiro,
        y.icms_cst,
        y.valor_bilhete,
        y.infvalorbpe_vDesconto as valor_desconto,
        y.pago as valor_pago,
        
        -- o select abaixo faz a divisão do valor da saída no BPe (por chave de acesso) pelo total de saídas (CTe/BPe), depois multiplica pelo total das entradas em EFD (RO) ou soma de NFe (Fora de RO), econtrando o rateio das entradas.
        -- caso o município do emitente comece por 11 (RO) utilizamos os dados da EFD, senão utilizamos os dados das compras informadas em notas fiscais.
                                    
          --------------------------------------------------------------------------------------------------------------------------------                          
                                    
         case when y.enderemit_cmun like '11%' then (case when (nvl(x.sumcte,0)+nvl(y.sumbpe,0)) = 0 then 0 else nvl(round((z.soper)*y.pago/(nvl(x.sumcte,0)+nvl(y.sumbpe,0)),2),0) end)
                                    else (case when (nvl(x.sumcte,0)+nvl(y.sumbpe,0)) = 0 then 0 else nvl(round((w.sprod)*y.pago/(nvl(x.sumcte,0)+nvl(y.sumbpe,0)),2),0) end) end as rateio_entrada,

         y.pago - 
         case when y.enderemit_cmun like '11%' then (case when (nvl(x.sumcte,0)+nvl(y.sumbpe,0)) = 0 then 0 else nvl(round((z.soper)*y.pago/(nvl(x.sumcte,0)+nvl(y.sumbpe,0)),2),0) end)
                                            else (case when (nvl(x.sumcte,0)+nvl(y.sumbpe,0)) = 0 then 0 else nvl(round((w.sprod)*y.pago/(nvl(x.sumcte,0)+nvl(y.sumbpe,0)),2),0) end) end as valor_liquido                          
                                    
                                    

         
         from tab_bpe y
         
         left join tab_cte x on y.ano_cnpj = x.ano_cnpj
         left join tab_efd z on y.ano_cnpj = z.ano_cnpj 
         left join tab_nff w on y.ano_cnpj = w.ano_cnpj
         
            ) j LEFT JOIN BI.DM_LOCALIDADE l on l.co_municipio = j.cod_munini
                left join bi.dm_pessoa p on p.co_cnpj_cpf = j.cnpj
                
            
            group by 
            extract(year from j.dhemi), 
            j.uf_inicio, 
            --j.uf_fim, 
            j.cod_munini, 
            l.no_municipio, 
            --j.cod_munfim, 
            j.cnpj, 
            p.no_razao_social,
            p.co_municipio,
            p.co_regime_pagto

