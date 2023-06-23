-- Trigger: new_document_trigger

-- DROP TRIGGER IF EXISTS new_document_trigger ON public."fe_pos";

CREATE TRIGGER new_document_trigger
    AFTER INSERT OR UPDATE 
    ON public."fe_pos"
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_newdocument();