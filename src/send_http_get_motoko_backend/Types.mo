module {
    // HTTP Request related types
    public type HttpMethod = {
        #get;
        #post;
        #head;
    };

    public type HttpHeader = {
        name : Text;
        value : Text;
    };

    public type HttpRequestArgs = {
        url : Text;
        max_response_bytes : ?Nat64;
        headers : [HttpHeader];
        body : ?[Nat8];
        method : HttpMethod;
        transform : ?TransformContext;
    };

    // HTTP Response related types
    public type HttpResponsePayload = {
        status : Nat;
        headers : [HttpHeader];
        body : [Nat8];
    };

    public type CanisterHttpResponsePayload = HttpResponsePayload;

    // Transform related types
    public type TransformArgs = {
        response : HttpResponsePayload;
        context : Blob;
    };

    public type TransformContext = {
        function : shared query TransformArgs -> async CanisterHttpResponsePayload;
        context : Blob;
    };

    // External service interface
    public type ExternalService = actor {
        http_request : shared HttpRequestArgs -> async HttpResponsePayload;
    };
}