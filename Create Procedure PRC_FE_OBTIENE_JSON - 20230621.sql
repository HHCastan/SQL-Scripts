DECLARE @FECHA VARCHAR(8)='20230209'
DECLARE @ALMACEN VARCHAR(8)='01'
DECLARE @TRM VARCHAR(8)='1'
DECLARE @TRAN VARCHAR(8)='11'
DECLARE @IMPT_BOLSA VARCHAR(12)='108046853797';
-- Borra tablas temporales:
IF OBJECT_ID('tempdb..#TMP_VTADPT_DET')       IS NOT NULL DROP TABLE #TMP_VTADPT_DET       -- Depto detalles por articulos
IF OBJECT_ID('tempdb..#TMP_VTADPT_DET_FINAL') IS NOT NULL DROP TABLE #TMP_VTADPT_DET_FINAL -- Detalles para productos propios
IF OBJECT_ID('tempdb..#TMP_VTADPT_PRO')       IS NOT NULL DROP TABLE #TMP_VTADPT_PRO       -- Depto para productos propios
IF OBJECT_ID('tempdb..#TMP_VTADPT_MND')       IS NOT NULL DROP TABLE #TMP_VTADPT_MND       -- Depto para productos de terceros
IF OBJECT_ID('tempdb..#TMP_VTAMP')            IS NOT NULL DROP TABLE #TMP_VTAMP            -- Encabezado de VTAXMP
IF OBJECT_ID('tempdb..#TMP_VTAMP_DET')        IS NOT NULL DROP TABLE #TMP_VTAMP_DET        -- Detalle de VTAXMP
IF OBJECT_ID('tempdb..#TMP_VTAMP_DET_MP')     IS NOT NULL DROP TABLE #TMP_VTAMP_DET_MP     -- Lineal de VTAXMP
IF OBJECT_ID('tempdb..#TMP_BONO_CAMBIO')      IS NOT NULL DROP TABLE #TMP_BONO_CAMBIO      -- Ajuste al cambio
IF OBJECT_ID('tempdb..#TMP_DCTO_GASTO')       IS NOT NULL DROP TABLE #TMP_DCTO_GASTO       -- Ajuste al cambio
IF OBJECT_ID('tempdb..#TMP_FISCAL')           IS NOT NULL DROP TABLE #TMP_FISCAL           -- Consecutivo fiscal
IF OBJECT_ID('tempdb..#TMP_ALMACEN')          IS NOT NULL DROP TABLE #TMP_ALMACEN          -- Datos del almacen
IF OBJECT_ID('tempdb..#TMP_VTAIVA_LINEAL')    IS NOT NULL DROP TABLE #TMP_VTAIVA_LINEAL    -- Detalle de impuestos
IF OBJECT_ID('tempdb..#TMP_VTAIVA_DET')       IS NOT NULL DROP TABLE #TMP_VTAIVA_DET       -- Lineal de impuestos
-- Crea tablas temporales:
--
-- Tabla con todos los detalles:
SELECT ROW_NUMBER() OVER(ORDER BY VD.CODIGO) AS 'RowNumber'
      , VD.*
      , ROUND((VD.PRECIO / (1 + VD.PORCENTAJE / 100.0)),2,0) AS TOTAL_BRUTO
      , ROUND((VD.DESCUENTO / (1 + VD.PORCENTAJE / 100.0)),2,0) AS TOTAL_DESCUENTO
      , LEFT(PR.PRD_DESC, 18) DESCRIPCION
INTO #TMP_VTADPT_DET
FROM (SELECT CODIGO
           , SUM(CANTIDAD) CANTIDAD
           , SUM(PRECIO) PRECIO
           , SUM(DESCUENTO)DESCUENTO
           , TERM
           , TRX
           , REMISION
           , FECHA_HORA
           , REC1
           , SUM(ROUND(IVA,2,0)) IVA
           , SUM(ROUND(NETO,2,0)) NETO
           , FAMILY
           , FECHA_POS
           , HORA_POS
           , ALMACEN_POS
           , MIN(INDICAT3) INDICAT3
           , PORCENTAJE
           , DESC_IVA
      FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[VST_DEPTO_HISTORICO] 
      WHERE FECHA_POS   = @FECHA
        AND ALMACEN_POS = @ALMACEN
	AND TERM        = RIGHT('000'+@TRM,3)
	AND TRX         = RIGHT('0000'+@TRAN,4)
      GROUP BY CODIGO
              ,TERM
              ,TRX
              ,REMISION
              ,FECHA_HORA
              ,REC1
              ,FAMILY
              ,FECHA_POS
              ,HORA_POS
              ,ALMACEN_POS
              ,PORCENTAJE
              ,DESC_IVA
      HAVING SUM(NETO)   <> 0
      ) VD
LEFT JOIN PRODUCT PR ON PR.PRD_CODE COLLATE SQL_Latin1_General_CP1_CI_AS = VD.CODIGO
--
-- Tabla de notas para articulos propios:
SELECT NRO_LINEAS               = COUNT(1), 
       VALORTOTAL_TOTAL_BRUTO   = SUM(TOTAL_BRUTO),
       VALORTOTAL_DESCUENTOS    = SUM(TOTAL_DESCUENTO),
       VALORTOTAL_SUBTOTAL      = SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO), 
       VALORTOTAL_IVA           = ROUND(SUM(IVA), 2),
       VALORTOTAL_TOTAL_A_PAGAR = ROUND(SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) + SUM(IVA), 2),
       VALORTOTAL_BASE_TOTAL    = ROUND(SUM(NETO), 2),
       VALORTOTAL_BASE_GBLE     = ROUND(SUM(NETO * (CASE WHEN RIGHT(INDICAT3,1) = 9 THEN 0 ELSE 1 END)), 2) -- Cero si es excluido (Dia sin IVA)
INTO #TMP_VTADPT_PRO
FROM #TMP_VTADPT_DET
GROUP BY LEFT(INDICAT3,1)
HAVING LEFT(INDICAT3,1) <> 4
--
-- Tabla de notas para mandatos:
SELECT NRO_LINEAS               = COUNT(1), 
       VALORTOTAL_TOTAL_BRUTO   = SUM(TOTAL_BRUTO),
       VALORTOTAL_DESCUENTOS    = SUM(TOTAL_DESCUENTO),
       VALORTOTAL_SUBTOTAL      = SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO), 
       VALORTOTAL_IVA           = ROUND(SUM(IVA), 2),
       VALORTOTAL_TOTAL_A_PAGAR = ROUND(SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) + SUM(IVA), 2),
       VALORTOTAL_BASE_TOTAL    = (SELECT COALESCE(ROUND(SUM(NETO), 2), 0) FROM #TMP_VTADPT_DET WHERE LEFT(INDICAT3,1) = 4 AND CODIGO <> @IMPT_BOLSA),
       VALORTOTAL_BASE_GBLE     = (SELECT COALESCE(ROUND(SUM(NETO), 2), 0) FROM #TMP_VTADPT_DET WHERE LEFT(INDICAT3,1) = 4 AND CODIGO <> @IMPT_BOLSA)
INTO #TMP_VTADPT_MND
FROM #TMP_VTADPT_DET
GROUP BY LEFT(INDICAT3,1)
HAVING LEFT(INDICAT3,1) = 4
-- Agrega registro en ceros por si no hubo mandatos
INSERT INTO #TMP_VTADPT_MND
SELECT 1,0,0,0,0,0,0,0 
FROM #TMP_VTADPT_MND
HAVING (SELECT COUNT(1) FROM #TMP_VTADPT_MND) < 1
--
-- Tabla para el encabezado:
SELECT IDTransaccionM = (RIGHT(FECHA_POS, 6) +RIGHT(TERMINAL, 3)+ TRANSACCION + ALMACEN_POS)
     , VentaNetoM     = ROUND(SUM(VALOR),0)
     , CLIENTE        = SUBSTRING(NUMERO_CLIENTE,PATINDEX('%[^0]%',NUMERO_CLIENTE+'.'),LEN(NUMERO_CLIENTE))
     , TERMINAL       
     , FECHA          = SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
     , HORA           = SUBSTRING(HORA_POS,1,2) + ':' + SUBSTRING(HORA_POS,3,2) + ':00-05:00'
     , DCTO_GASTO     = ROUND (SUM(CASE WHEN MEDIO_PAGO IN (81, 82, 84) THEN VALOR ELSE 0 END), 0)
     , AJUSTE_CAMBIO  = ROUND (SUM(CASE WHEN MEDIO_PAGO = 83 THEN VALOR ELSE 0 END), 0)
     , MAX(CUOTAS) CUOTAS
INTO #TMP_VTAMP
FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[VST_MP_HISTORICO_SIGNO] O
         WHERE TERMINAL = RIGHT('0000'+@TRM,4)
             AND ALMACEN_POS = @ALMACEN
             AND TRANSACCION = RIGHT('0000'+@TRAN,4)
             AND FECHA_POS = @FECHA
         GROUP BY(RIGHT(FECHA_POS, 6) +RIGHT(TERMINAL, 3)+ TRANSACCION + ALMACEN_POS)
              , FECHA_HORA
              , ALMACEN_POS
              , TERMINAL
              , TRANSACCION
              , SUBSTRING(NUMERO_CLIENTE,PATINDEX('%[^0]%',NUMERO_CLIENTE+'.'),LEN(NUMERO_CLIENTE))
              , SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
              , SUBSTRING(HORA_POS,1,2) + ':' + SUBSTRING(HORA_POS,3,2) + ':00-05:00'
--
-- Tabla para el detalle de los medios de pago:
SELECT MEDIO_PAGO
     , SUM(VALOR) SUMA
     , FECHA = SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
     , MP_NOMBRE = DESCRIPCION
     , ROW_NUMBER() OVER(ORDER BY MEDIO_PAGO) AS 'RowNumber'
INTO #TMP_VTAMP_DET
FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[VST_MP_HISTORICO_SIGNO] O
INNER JOIN [LINKINFORMESPOS].[INFORMESPOS].dbo.[MEDIOS_DE_PAGO] N ON O.MEDIO_PAGO = N.TIPOVARIEDAD
         WHERE TERMINAL = RIGHT('0000'+@TRM,4)
             AND MEDIO_PAGO NOT IN (81, 82, 83, 84)
             AND ALMACEN_POS = @ALMACEN
             AND TRANSACCION = RIGHT('0000'+@TRAN,4)
             AND FECHA_POS = @FECHA
GROUP BY MEDIO_PAGO,SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2),DESCRIPCION
--
-- Tabla lineal con los medios de pago:
SELECT
   paymentMeansId     = CAST(RowNumber AS VARCHAR(4)) 
   , paymentMeansCode = MEDIO_PAGO
   , paymentDueDate   = FECHA 
   , paymentID        = MP_NOMBRE
INTO #TMP_VTAMP_DET_MP
FROM #TMP_VTAMP_DET
--
-- Tabla con las tarifas de impuestos:
SELECT TotalBase = LTRIM(STR(SUM(CASE WHEN CODIGO = @IMPT_BOLSA THEN 0.0 ELSE NETO END), 10, 2))
     , TotalIVA  = LTRIM(STR(SUM(CASE WHEN CODIGO = @IMPT_BOLSA THEN NETO ELSE IVA END), 10, 2))
     , PORCENTAJE 
INTO #TMP_VTAIVA_DET
FROM #TMP_VTADPT_DET
GROUP BY PORCENTAJE
--
-- Tabla lineal con las tarifas de impuestos:
SELECT
     taxableAmountCurrency    = 'COP'
   , taxableAmountValue       = TotalBase
   , taxAmountCurrency        = 'COP'
   , taxAmountValue           = TotalIVA
   , taxSchemeId              = '01'
   , taxSchemeName            = 'IVA'
   , taxPercent               = LTRIM(STR(PORCENTAJE, 10, 2))
   , baseUnitMeasureUnitCode  = ''                             -- Un campo vacio que no tengo idea
   , baseUnitMeasureValue     = ''                             -- Un campo vacio que no tengo idea
   , perUnitAmoutCurrencyCode = ''                             -- Un campo vacio que no tengo idea
   , perUnitAmoutValue        = ''                             -- Un campo vacio que no tengo idea
INTO #TMP_VTAIVA_LINEAL
FROM #TMP_VTAIVA_DET
--
-- Tabla para el detalle de todos los articulos:
CREATE TABLE #TMP_VTADPT_DET_FINAL (
       lineSchemeId                                     VARCHAR(30)
     , lineId                                           VARCHAR(30)
     , invoicedQuantityValue                            VARCHAR(30)
     , lineExtensionAmountInvoiceLineCurrencyCode       VARCHAR(30)
     , lineExtensionAmountInvoiceLineValue              VARCHAR(30)
     , taxAmountTaxTotalInvoiceLineCurrencyCode         VARCHAR(30)
     , taxAmountTaxTotalInvoiceLineValue                VARCHAR(30)
     , roundingAmountTaxTotalInvoiceLineCurrencyCode    VARCHAR(30)
     , roundingAmountTaxTotalInvoiceLineValue           VARCHAR(30)
     , idStandardItemIdentificationValue                VARCHAR(30)
     , lineItemDescription                              VARCHAR(30)
     , priceAmountCurrencyCode                          VARCHAR(30)
     , priceAmountValue                                 VARCHAR(30)
     , unitCode                                         VARCHAR(30)
     , baseQuantityValue                                VARCHAR(30)
     , subtotal                                         VARCHAR(30)
     , subtotalConImpuesto                              VARCHAR(30)
     , mndtSubtotal                                     VARCHAR(30)
     , mndtSubtotalConImpuesto                          VARCHAR(30)
     , priceAmountAlertnativeConditionPriceCurrencyCode VARCHAR(30)
     , priceAmountAlertnativeConditionPriceValue        VARCHAR(30)
     , taxableAmountCurrency                            VARCHAR(30)
     , taxableAmountValue                               VARCHAR(30)
     , taxAmountCurrency                                VARCHAR(30)
     , taxAmountValue                                   VARCHAR(30)
     , taxSchemeId                                      VARCHAR(30)
     , taxSchemeName                                    VARCHAR(30)
     , taxPercent                                       VARCHAR(30)
     , baseUnitMeasureUnitCode                          VARCHAR(30)
     , baseUnitMeasureValue                             VARCHAR(30)
     , perUnitAmoutCurrencyCode                         VARCHAR(30)
     , perUnitAmoutValue                                VARCHAR(30)
     , amountValue                                      VARCHAR(30)
     , amountAllowanceChargeCurrencyCode                VARCHAR(30)
     , idAllowanceCharge                                VARCHAR(30)
     , chargeIndicator                                  VARCHAR(30)
     , allowaneChargeReasonCode                         VARCHAR(30)
     , allowaneChargeReason                             VARCHAR(30)
     , multiplierFactorNumeric                          VARCHAR(30)
     , baseAmountAllowanceChargeCurrencyCode            VARCHAR(30)
     , baseAmountValue                                  VARCHAR(30)
 )
INSERT INTO #TMP_VTADPT_DET_FINAL
SELECT 
      '0'                                          -- Tipo 0: Propio - lineSchemeId                                  
      ,CAST(RowNumber AS VARCHAR(4))               -- Posicion - lineId                                        
      ,LTRIM(STR(CANTIDAD, 10, 2))                 -- invoicedQuantityValue                         
      ,'COP'                                       -- monedaValorBruto - lineExtensionAmountInvoiceLineCurrencyCode    
      ,LTRIM(STR(NETO, 10, 2))                     -- valorBruto - lineExtensionAmountInvoiceLineValue           
      ,'COP'                                       -- monedaTotalImpuestos - taxAmountTaxTotalInvoiceLineCurrencyCode      
      ,LTRIM(STR(IVA, 10, 2))                      -- valorTotalImpuestos - taxAmountTaxTotalInvoiceLineValue             
      ,'COP'                                       -- monedaRedondeoTotal - roundingAmountTaxTotalInvoiceLineCurrencyCode 
      ,'0.00'                                      -- valorRedondeoTotal - roundingAmountTaxTotalInvoiceLineValue
      ,CODIGO                                      -- idStandardItemIdentificationValue                                     
      ,DESCRIPCION                                 -- lineItemDescription - lineItemDescription
      ,'COP'                                       -- monedaPrecio - priceAmountCurrencyCode
      ,LTRIM(STR(TOTAL_BRUTO, 10, 2))              -- valorPrecio  - priceAmountValue
      ,'ZZ'                                        -- codigo Unidad de medida - unitCode
      ,LTRIM(STR(CANTIDAD, 10, 2))                 -- baseQuantityValue
      ,LTRIM(STR(PRECIO - DESCUENTO - IVA, 10, 2)) -- Subtotal
      ,LTRIM(STR(NETO + IVA, 10, 2))               -- Subotal con impuestos
      ,'0.00'                                      -- Mandato Subtotal. Cero por ser bloque de propios
      ,'0.00'                                      -- Mandato Subtotal con impuestos. Cero por ser bloque de propios
      ,'COP'                                       -- Moneda para la bolsa - priceAmountAlertnativeConditionPriceCurrencyCode
      ,'0.00'                                      -- Valor para la bolsa - priceAmountAlertnativeConditionPriceValue
      ,'COP'                                       -- monedaBase - taxableAmountCurrency
      ,LTRIM(STR(NETO, 10, 2))                     -- valorBase - taxableAmountValue
      ,'COP'                                       -- monedaImpuesto - taxAmountCurrency
      ,LTRIM(STR(IVA, 10, 2))                      -- valorImpuesto - taxAmountValue
      ,CASE WHEN CODIGO = @IMPT_BOLSA 
          THEN '22' 
          ELSE '01' 
       END                                         -- codigoImpuesto - taxSchemeId
      ,CASE WHEN CODIGO = @IMPT_BOLSA              
          THEN 'INC Bolsas'                        
          ELSE 'IVA'                               
       END                                         -- nombreImpuesto - taxSchemeName
      ,LTRIM(STR(ROUND(PORCENTAJE, 0), 10, 2))     -- porcentajeImpuesto - taxPercent
      ,CASE WHEN CODIGO = @IMPT_BOLSA              
          THEN '94'                                
          ELSE ''                                  
       END                                         -- codigoBolsas
      ,CASE WHEN CODIGO = @IMPT_BOLSA 
          THEN LTRIM(STR(CANTIDAD, 10, 2)) 
          ELSE '' 
       END                                         -- cantidadBolsas
      ,CASE WHEN CODIGO = @IMPT_BOLSA              
          THEN 'COP'                               
          ELSE ''                                  
       END                                         -- monedaValorBolsas
      ,CASE WHEN CODIGO = @IMPT_BOLSA              
          THEN LTRIM(STR(PRECIO, 10, 2))           
          ELSE ''                                  
       END                                         -- valor (Bolsas)
      ,LTRIM(STR(TOTAL_DESCUENTO, 10, 2))          -- valor (descuento)
      ,'COP'                                       -- monedaValorDescuento
      ,'1'                                         -- consecutivo
      ,'false'                                     -- esCargo
      ,'9999DCTO01'                                -- ID constante por ser contingencia
      ,'Descuento producto'                        -- Constante por ser contingencia
      ,LTRIM(STR(ROUND(TOTAL_DESCUENTO         
       / TOTAL_BRUTO * 100.0, 2), 10, 2))          -- porcentaje de descuento
      ,'COP'                                       -- monedaBase
      ,LTRIM(STR(TOTAL_BRUTO, 10, 2))              -- valorBase
FROM #TMP_VTADPT_DET
WHERE LEFT(INDICAT3,1) <> 4
--
-- Agrega los mandatos a #TMP_VTADPT_DET_FINAL:
INSERT INTO #TMP_VTADPT_DET_FINAL 
SELECT
   '1'                                          -- Tipo 1: Mandato - lineSchemeId   
   , CAST(RowNumber AS VARCHAR(4))              -- Posicion - lineId   
   , LTRIM(STR(CANTIDAD, 10, 2))                -- invoicedQuantityValue 
   , 'COP'                                      -- monedaValorBruto - lineExtensionAmountInvoiceLineCurrencyCode    
   , CASE WHEN CODIGO = @IMPT_BOLSA             
         THEN '0.00'                            
         ELSE LTRIM(STR(NETO, 10, 2)) END       -- valorBruto - lineExtensionAmountInvoiceLineValue           
   , 'COP'                                      -- monedaTotalImpuestos - taxAmountTaxTotalInvoiceLineCurrencyCode      
   , CASE WHEN CODIGO = @IMPT_BOLSA             
         THEN LTRIM(STR(NETO, 10, 2))           
         ELSE LTRIM(STR(ROUND(IVA, 0), 10, 2))  
         END                                    -- valorTotalImpuestos - taxAmountTaxTotalInvoiceLineValue             
   , 'COP'                                      -- monedaRedondeoTotal - roundingAmountTaxTotalInvoiceLineCurrencyCode 
   , '0.00'                                     -- valorRedondeoTotal - roundingAmountTaxTotalInvoiceLineValue
   , CODIGO                                     -- idStandardItemIdentificationValue                                     
   , DESCRIPCION                                -- lineItemDescription - lineItemDescription
   , 'COP'                                      -- monedaPrecio - priceAmountCurrencyCode
   , CASE WHEN CODIGO = @IMPT_BOLSA             
         THEN '0.00'                            
         ELSE LTRIM(STR(TOTAL_BRUTO, 10, 2))    
     END                                        -- valorPrecio  - priceAmountValue
   , 'ZZ'                                       -- codigo Unidad de medida - unitCode
   , LTRIM(STR(CANTIDAD, 10, 2))                -- baseQuantityValue
   , '0.00'                                     -- Subtotal. Cero por ser bloque de mandatos
   , '0.00'                                     -- Subtotal con impuestos. Cero por ser bloque de mandatos
   , LTRIM(STR(ROUND(PRECIO -                  
                   DESCUENTO -                 
                   IVA, 0), 10, 2))             -- Mandato Subtotal
   , LTRIM(STR(ROUND(NETO + IVA, 0), 10, 2))    -- Mandato Subotal con impuestos
   , CASE WHEN CODIGO = @IMPT_BOLSA
         THEN 'COP'   
         ELSE '' END                            -- Moneda para la bolsa - priceAmountAlertnativeConditionPriceCurrencyCode
   , CASE WHEN CODIGO = @IMPT_BOLSA
         THEN LTRIM(STR(NETO, 10, 2))   
         ELSE '' END                            -- Valor para la bolsa - priceAmountAlertnativeConditionPriceValue
   , 'COP'                                      -- monedaBase - taxableAmountCurrency
   , CASE WHEN CODIGO = @IMPT_BOLSA             
         THEN '0.00'                            
         ELSE LTRIM(STR(ROUND(NETO, 0), 10, 2))
     END                                        -- valorBase - taxableAmountValue
   , 'COP'                                      -- monedaImpuesto - taxAmountCurrency
   , CASE WHEN CODIGO = @IMPT_BOLSA
          THEN LTRIM(STR(NETO, 10, 2))   
          ELSE LTRIM(STR(ROUND(IVA, 0), 10, 2))
     END                                        -- valorImpuesto - taxAmountValue
   , CASE WHEN CODIGO = @IMPT_BOLSA 
         THEN '22' 
         ELSE '01' 
      END                                       -- codigoImpuesto - taxSchemeId
   , CASE WHEN CODIGO = @IMPT_BOLSA            
        THEN 'INC Bolsas'                      
        ELSE 'IVA'                             
     END                                       -- nombreImpuesto - taxSchemeName
   , LTRIM(STR(ROUND(PORCENTAJE, 0), 10, 2))   -- porcentajeImpuesto - taxPercent
   , CASE WHEN CODIGO = @IMPT_BOLSA            
        THEN '94'                              
        ELSE ''                                
     END                                       -- codigoBolsas
   , CASE WHEN CODIGO = @IMPT_BOLSA            
        THEN LTRIM(STR(CANTIDAD, 10, 2))       
        ELSE ''                                
     END                                       -- cantidadBolsas
   , CASE WHEN CODIGO = @IMPT_BOLSA            
        THEN 'COP'                             
        ELSE ''                                
     END                                       -- monedaValorBolsas
   ,CASE WHEN CODIGO = @IMPT_BOLSA             
        THEN LTRIM(STR(PRECIO, 10, 2))         
        ELSE ''                                
     END                                       -- valor (Bolsas)
   , LTRIM(STR(TOTAL_DESCUENTO, 10, 2))        -- valor (descuento)
   , 'COP'                                     -- monedaValorDescuento
   , '1'                                       -- consecutivo
   , 'false'                                   -- esCargo
   , '9999DCTO01'                              -- ID constante por ser contingencia
   , 'Descuento producto'                      -- Constante por ser contingencia
   , LTRIM(STR(ROUND(TOTAL_DESCUENTO           
     / TOTAL_BRUTO * 100.0, 2), 10, 2))        -- porcentaje de descuento
   , 'COP'                                     -- monedaBase
   , LTRIM(STR(TOTAL_BRUTO, 10, 2))            -- valorBase
FROM #TMP_VTADPT_DET
WHERE LEFT(INDICAT3,1) = 4
--
-- Tabla para el ajuste al cambio y descuentos al gasto:
CREATE TABLE #TMP_DCTO_GASTO (amountValue                              DEC(10,2)
                             , baseAmountValue                         DEC(10,2)
                             , idAllowanceCharge                       VARCHAR(2) -- ID ficticio
                             , chargeIndicator                         VARCHAR(5) -- Consecutivo registro
                             , allowaneChargeReasonCode                VARCHAR(2)
                             , allowaneChargeReason                    VARCHAR(19)
                             , multiplierFactorNumeric                 DEC(6,2)
                             , amountAllowanceChargeCurrencyCode       VARCHAR(3)
                             , baseAmountAllowanceChargeCurrencyCode   VARCHAR(3)
) 
INSERT INTO #TMP_DCTO_GASTO
SELECT TOP 1 LTRIM(STR(VALOR,10,2))
     , T.TOTAL_BRUTO
     , T.CONSECUTIVO
     , T.ESCARGO
     , T.ID
     , T.DESCRIPCION
     , LTRIM(STR(T.PORCENTAJE, 10, 2))
     , 'COP'
     , 'COP'
FROM
(
    SELECT '0' VALOR
         , 'DESCUENTOS AL GASTO' DESCRIPCION
         , '1' CONSECUTIVO
         , 'false' ESCARGO
         , '0' PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '02' ID 
    FROM #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    UNION
    SELECT VALOR
         , 'DESCUENTOS AL GASTO' DESCRIPCION
         , '1' CONSECUTIVO
         , 'false' ESCARGO
         , LTRIM(STR(ROUND(VALOR / (DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO) * 100.0, 0),10, 2)) PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '02' ID 
    FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[VST_MP_HISTORICO_SIGNO], #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    WHERE FECHA_POS = @FECHA
        AND ALMACEN_POS = @ALMACEN
        AND TERMINAL = RIGHT('0000'+@TRM,4)
        AND TRANSACCION = RIGHT('0000'+@TRAN,4)
        AND MEDIO_PAGO IN (81, 82, 84)
) T
ORDER BY VALOR DESC
--
-- Agrega el descuento al gasto a #TMP_DCTO_GASTO:
INSERT INTO #TMP_DCTO_GASTO
SELECT TOP 1 LTRIM(STR(VALOR,10,2))
     , T.TOTAL_BRUTO
     , T.CONSECUTIVO
     , T.ESCARGO
     , T.ID
     , T.DESCRIPCION
     , LTRIM(STR(T.PORCENTAJE, 10, 2))
     , 'COP'
     , 'COP'
FROM
(
    SELECT '0' VALOR
         , 'BONO POR CAMBIO' DESCRIPCION
         , '2' CONSECUTIVO
         , 'false' ESCARGO
         , '0' PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    UNION
    SELECT VALOR
         , 'BONO POR CAMBIO' DESCRIPCION
         , '02' CONSECUTIVO
         , 'false' ESCARGO
         , LTRIM(STR(ROUND(VALOR / (DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO) * 100.0, 0),10, 2)) PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[VST_MP_HISTORICO_SIGNO], #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    WHERE FECHA_POS = @FECHA
        AND ALMACEN_POS = @ALMACEN
        AND TERMINAL = RIGHT('0000'+@TRM,4)
        AND TRANSACCION = RIGHT('0000'+@TRAN,4)
        AND MEDIO_PAGO = 83
) T
ORDER BY VALOR DESC
--
-- Tabla para el consecutivo fiscal
SELECT RIGHT(CONSECUTIVO_FISCAL,7) CONSECUTIVO
	, PREFIJO
	, RESOLUCION
	, FECHA_INI
	, FECHA_FIN
	, RANGO_INI
	, RANGO_FIN
INTO #TMP_FISCAL
FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[CONSEFISNEW_ALL]
WHERE FECHA_POS       = @FECHA
  AND ALMACEN_POS     = @ALMACEN
  AND NRO_TERMINAL    = RIGHT('0000'+@TRM,4)
  AND NRO_TRANSACCION = RIGHT('0000'+@TRAN,4)
--
-- Tabla para el almacen
SELECT *
INTO #TMP_ALMACEN
FROM [LINKINFORMESPOS].[INFORMESPOS].dbo.[ALMACENESNEW]
WHERE NUMERO = RIGHT('0000'+@ALMACEN,3)
--
-- La consulta final:
SELECT
     idTienda                            = RIGHT('000'+A.NUMERO,3)
     , idCaja                            = RIGHT('000'+@TRM,3)
     , idTransaccion                     = RIGHT('0000'+@TRAN,4)
     , documentoCliente                  = CASE WHEN M.CLIENTE = '999999999999' THEN '222222222222' ELSE M.CLIENTE END       -- Cliente
     , customizationID                   = CASE WHEN (SELECT SUM(VALORTOTAL_TOTAL_BRUTO) FROM #TMP_VTADPT_MND) > 0 
                                                THEN '11' ELSE '10' END -- 10 para trx normal, 11 cuando incluye mandado
     , profileExecutionID                = CASE WHEN A.PREFIJO = 'SE' THEN '2' ELSE '1' END                                  -- 2 para preubas, 1 para produccion
     , invoiceId                         = F.PREFIJO  + F.CONSECUTIVO 
     , issueDate                         = M.FECHA 
     , issueTime                         = M.HORA
     , invoiceTypeCode                   = '01'                                                                              --????????????????????
     , lineCountNumeric                  = (SELECT COUNT(1) FROM #TMP_VTADPT_DET_FINAL)                                      -- Contador lineas de la trx
     , resolucionNotes                   = 'AUTORIZACION DE NUMERACION~DE FACTURACION No.' + F.RESOLUCION                    -- resolucionNotes, RESOLUCION
                                           + '~RANGO ' + F.PREFIJO + RIGHT('00000' + F.RANGO_INI, 7) + ' - '                 -- resolucionNotes, RANGO FINAL
                                           + F.PREFIJO + RIGHT('00000' + F.RANGO_FIN,7)                                      -- resolucionNotes, RANGO FINAL
                                           + '~VIGENCIA: ' + F.FECHA_INI + ' HASTA ' + F.FECHA_FIN                           -- resolucionNotes, FECHAS
     , plazo                             = CONVERT(VARCHAR,CONVERT(INT, M.CUOTAS))                                           -- plazo del credito
     , subtotal                          = ''                                                                                -- campo vacio
     , subtotal_con_impto                = ''                                                                                -- campo vacio
     , valortotal_total_bruto            = LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO, 10, 2)) 
     , valortotal_descuentos             = LTRIM(STR(DP.VALORTOTAL_DESCUENTOS, 10, 2))
     , valortotal_subtotal               = LTRIM(STR(DP.VALORTOTAL_SUBTOTAL, 10, 2))
     , valortotal_iva                    = LTRIM(STR(DP.VALORTOTAL_IVA, 10, 2)) 
     , valortotal_total_a_pagar          = LTRIM(STR(DP.VALORTOTAL_TOTAL_A_PAGAR, 10, 2))
     , mndt_subtotal                     = LTRIM(STR(DM.VALORTOTAL_SUBTOTAL, 10, 2))                                         -- 
     , mndt_subtotal_con_impto           = '0.00'                                                                            -- 
     , mndt_valortotal_total_bruto       = LTRIM(STR(DM.VALORTOTAL_TOTAL_BRUTO, 10, 2))
     , mndt_valortotal_descuentos        = LTRIM(STR(DM.VALORTOTAL_DESCUENTOS, 10, 2)) 
     , mndt_valortotal_subtotal          = LTRIM(STR(DM.VALORTOTAL_SUBTOTAL, 10, 2))
     , mndt_valortotal_iva               = LTRIM(STR(DM.VALORTOTAL_IVA, 10, 2))
     , mndt_valortotal_total_a_pagar     = LTRIM(STR(DM.VALORTOTAL_TOTAL_A_PAGAR, 10, 2))
     , otros_descuentos                  = LTRIM(STR((SELECT SUM(amountValue) FROM #TMP_DCTO_GASTO), 10, 2))                 -- Dcto. Gasto + Bono Cambio
     , startDate                         = M.FECHA
     , startTime                         = '00:01:00-05:00'
     , endDate                           = M.FECHA
     , endTime                           = '23:59:59-05:00'
     , corporateRegistrationSchemeId     = F.PREFIJO  
     , taxAmountCurrencyCode             = 'COP'                                                                             -- Moneda del total del IVA
     , taxAmountValue                    = LTRIM(STR((DP.VALORTOTAL_IVA + DM.VALORTOTAL_IVA), 10, 2))                        -- IVA total
     , roundingAmountValue               = '0.00'                                                                            -- Redondeo del calculo del IVA
     , lineExtensionAmountValue          = LTRIM(STR((DP.VALORTOTAL_BASE_TOTAL + DM.VALORTOTAL_BASE_TOTAL), 10, 2))          -- Subtotal valor de los articulos
     , taxExclusiveAmountValue           = LTRIM(STR((DP.VALORTOTAL_BASE_GBLE + DM.VALORTOTAL_BASE_GBLE), 10, 2))            -- sumatoria de la base imponible total
     , taxInclusiveAmountValue           = LTRIM(STR((DP.VALORTOTAL_TOTAL_A_PAGAR + DM.VALORTOTAL_TOTAL_A_PAGAR), 10, 2))    -- sumatoria del total bruto
     , payableAmountValue                = LTRIM(STR((DP.VALORTOTAL_TOTAL_A_PAGAR + DM.VALORTOTAL_TOTAL_A_PAGAR 
                                                                                  - M.DCTO_GASTO - M.AJUSTE_CAMBIO), 10, 2)) -- Total a pagar
     , roundingAmountCurrencyCode        = 'COP' 
     , lineExtensionAmountCurrencyCode   = 'COP' 
     , taxExclusiveAmountCurrencyCode    = 'COP' 
     , taxInclusiveAmountCurrencyCode    = 'COP' 
     , payableAmountCurrencyCode         = 'COP' 
     , invoiceCurrencyCode               = 'COP' 
     , (SELECT lineSchemeId                                     
             , lineId                                           
             , invoicedQuantityValue                            
             , lineExtensionAmountInvoiceLineCurrencyCode       
             , lineExtensionAmountInvoiceLineValue              
             , taxAmountTaxTotalInvoiceLineCurrencyCode         
             , taxAmountTaxTotalInvoiceLineValue                
             , roundingAmountTaxTotalInvoiceLineCurrencyCode    
             , roundingAmountTaxTotalInvoiceLineValue           
             , idStandardItemIdentificationValue                
             , lineItemDescription                              
             , priceAmountCurrencyCode                          
             , priceAmountValue                                 
             , unitCode                                         
             , baseQuantityValue                                
             , subtotal                                         
             , subtotalConImpuesto                              
             , mndtSubtotal                                     
             , mndtSubtotalConImpuesto                          
             , CASE WHEN idStandardItemIdentificationValue = @IMPT_BOLSA THEN priceAmountAlertnativeConditionPriceCurrencyCode END AS priceAmountAlertnativeConditionPriceCurrencyCode
             , CASE WHEN idStandardItemIdentificationValue = @IMPT_BOLSA THEN priceAmountAlertnativeConditionPriceValue END AS priceAmountAlertnativeConditionPriceValue
             , (SELECT   taxableAmountCurrency           
                       , taxableAmountValue       
                       , taxAmountCurrency        
                       , taxAmountValue           
                       , taxSchemeId              
                       , taxSchemeName            
                       , taxPercent               
                       , baseUnitMeasureUnitCode  
                       , baseUnitMeasureValue     
                       , perUnitAmoutCurrencyCode 
                       , perUnitAmoutValue
                 FROM #TMP_VTADPT_DET_FINAL Xb WHERE Xb.lineId = Xa.lineId
             	  FOR JSON PATH
                      ) AS taxes
             , (SELECT   amountValue                          
                       , amountAllowanceChargeCurrencyCode    
                       , idAllowanceCharge                    
                       , chargeIndicator                      
                       , allowaneChargeReasonCode             
                       , allowaneChargeReason                 
                       , multiplierFactorNumeric              
                       , baseAmountAllowanceChargeCurrencyCode
                       , baseAmountValue                      
                 FROM #TMP_VTADPT_DET_FINAL Xc WHERE Xc.lineId = Xa.lineId
             	  FOR JSON PATH
                      ) AS allowanceCharges
             FROM #TMP_VTADPT_DET_FINAL Xa ORDER BY lineId
             FOR JSON PATH ) AS lines
     , (SELECT * FROM #TMP_VTAMP_DET_MP     FOR JSON PATH) AS payments                               -- Detalle de medios de pago
     , (SELECT * FROM #TMP_VTAIVA_LINEAL    FOR JSON PATH) AS totalTaxes                             -- Detalle de los impuestos
--     , (SELECT * FROM #TMP_DCTO_GASTO G WHERE G.amountValue > 0 FOR JSON PATH) AS allowanceCharge    -- Detalle otros descuentos     
     , (SELECT * FROM #TMP_DCTO_GASTO FOR JSON PATH) AS allowanceCharge                              -- Detalle otros descuentos     
     , payableRoundingAmountCurrencyCode = 'COP'                                                     -- Moneda del redondeo del total pagado
     , payableRoundingAmountValue = '0.00'                                                           
     , allowanceTotalAmountCurrencyCode  = 'COP'                                                     -- Moneda del total de la transaccion
     , allowanceTotalAmountValue = LTRIM(STR((SELECT SUM(amountValue) FROM #TMP_DCTO_GASTO), 10, 2)) -- Total otros descuentos
FROM
     #TMP_VTADPT_PRO DP FULL OUTER JOIN
     #TMP_VTADPT_MND DM ON 1=1,
     #TMP_VTAMP M,
     #TMP_FISCAL F,
     #TMP_ALMACEN A
FOR JSON PATH       
/**
SELECT * FROM #TMP_VTADPT_PRO DP
SELECT * FROM #TMP_VTADPT_MND DM
SELECT * FROM #TMP_VTAMP M
SELECT * FROM #TMP_VTAMP_DET_MP MD
SELECT * FROM #TMP_FISCAL F
SELECT * FROM #TMP_VTADPT_DET
SELECT * FROM #TMP_VTADPT_DET_FINAL
SELECT * FROM #TMP_VTAIVA_DET
SELECT * FROM #TMP_VTAIVA_LINEAL
SELECT * FROM #TMP_DCTO_GASTO
SELECT * FROM #TMP_ALMACEN A
**/
