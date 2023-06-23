
CREATE TABLE "public"."fe_pos"
(
   id_transaccion SERIAL PRIMARY KEY,
   prefijo varchar(4) NOT NULL,
   numero varchar(10) NOT NULL,
   xml_texto xml NOT NULL,
   xml_cufe text,
   xml_qr text,
   fecha_pos timestamp NOT NULL,
   transaccion varchar(4) NOT NULL,
   terminal varchar(4) NOT NULL,
   tienda_pos varchar(4) NOT NULL,
   estado smallint NOT NULL,
   observaciones text,
   fecha_proceso timestamp NOT NULL
)
;
