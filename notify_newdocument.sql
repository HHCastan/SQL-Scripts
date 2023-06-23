-- FUNCTION: public.notify_newdocument()

-- DROP FUNCTION IF EXISTS public.notify_newdocument();

CREATE OR REPLACE FUNCTION public.notify_newdocument()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
  BEGIN
  	IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW."ESTADO" = ANY ('{1,7}'::smallint[]))) THEN
      PERFORM pg_notify('new_document', NEW."ID_TRANSACCION"::text);
    END IF;
    
    RETURN NULL;
  END;
  
$BODY$;

ALTER FUNCTION public.notify_newdocument()
    OWNER TO postgres;
