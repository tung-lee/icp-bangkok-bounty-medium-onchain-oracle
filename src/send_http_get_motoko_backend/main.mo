import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Int "mo:base/Int";

//import the custom types you have in Types.mo
import Types "Types";


//Actor
actor {

    // Add state variables for time series storage
    private stable var priceHistory : [(Nat64, Float)] = [];
    private let MAX_HISTORY_LENGTH : Nat = 1000;  // Adjust as needed

    // Add timer functionality
    private stable var timer_id : Nat = 0;
    private let FETCH_INTERVAL : Nat64 = 60 * 1000_000_000;  // 1 minute in nanoseconds

    // Add method to store price data
    private func storePriceData(timestamp : Nat64, price : Float) {
        priceHistory := Array.append(
            priceHistory,
            [(timestamp, price)]
        );
        
        if (priceHistory.size() > MAX_HISTORY_LENGTH) {
            let newHistory = Array.init<(Nat64, Float)>(MAX_HISTORY_LENGTH, (0, 0));
            let startIndex = priceHistory.size() - MAX_HISTORY_LENGTH;
            
            var j = 0;
            while (j < MAX_HISTORY_LENGTH) {
                newHistory[j] := priceHistory[startIndex + j];
                j += 1;
            };
            
            priceHistory := Array.freeze(newHistory);
        };
    };

    // Add query method to get historical data
    public query func getPriceHistory() : async [(Nat64, Float)] {
        priceHistory
    };

    //This method sends a GET request to a URL with a free API you can test.
    //This method returns Coinbase data on the exchange rate between USD and ICP
    //for a certain day.
    //The API response looks like this:
    //  [
    //     [
    //         1682978460, <-- start timestamp
    //         5.714, <-- lowest price during time range
    //         5.718, <-- highest price during range
    //         5.714, <-- price at open
    //         5.714, <-- price at close
    //         243.5678 <-- volume of ICP traded
    //     ],
    // ]

    public func get_icp_usd_exchange() : async Text {

        //1. DECLARE MANAGEMENT CANISTER
        //You need this so you can use it to make the HTTP request
        let ic : Types.IC = actor ("aaaaa-aa");

        //2. SETUP ARGUMENTS FOR HTTP GET request

        // 2.1 Setup the URL and its query parameters
        let ONE_MINUTE : Nat64 = 60;
        let current_time = Nat64.fromNat(Int.abs(Time.now()));
        let start_timestamp : Types.Timestamp = current_time - ONE_MINUTE; // 1 minute ago
        let end_timestamp : Types.Timestamp = current_time;
        let host : Text = "api.exchange.coinbase.com";
        let url = "https://" # host # "/products/ICP-USD/candles?start=" # Nat64.toText(start_timestamp) # "&end=" # Nat64.toText(end_timestamp) # "&granularity=" # Nat64.toText(ONE_MINUTE);

        // 2.2 prepare headers for the system http_request call
        let request_headers = [
            { name = "Host"; value = host # ":443" },
            { name = "User-Agent"; value = "exchange_rate_canister" },
        ];

        // 2.2.1 Transform context
        let transform_context : Types.TransformContext = {
            function = transform;
            context = Blob.fromArray([]);
        };

        // 2.3 The HTTP request
        let http_request : Types.HttpRequestArgs = {
            url = url;
            max_response_bytes = null; //optional for request
            headers = request_headers;
            body = null; //optional for request
            method = #get;
            transform = ?transform_context;
        };

        //3. ADD CYCLES TO PAY FOR HTTP REQUEST

        //The IC specification spec says, "Cycles to pay for the call must be explicitly transferred with the call"
        //The management canister will make the HTTP request so it needs cycles
        //See: /docs/current/motoko/main/canister-maintenance/cycles

        //The way Cycles.add() works is that it adds those cycles to the next asynchronous call
        //"Function add(amount) indicates the additional amount of cycles to be transferred in the next remote call"
        //See: /docs/current/references/ic-interface-spec#ic-http_request
        Cycles.add(20_949_972_000);

        //4. MAKE HTTP REQUEST AND WAIT FOR RESPONSE
        //Since the cycles were added above, you can just call the management canister with HTTPS outcalls below
        let http_response : Types.HttpResponsePayload = await ic.http_request(http_request);

        //5. DECODE THE RESPONSE

        //As per the type declarations in `src/Types.mo`, the BODY in the HTTP response
        //comes back as [Nat8s] (e.g. [2, 5, 12, 11, 23]). Type signature:

        //public type HttpResponsePayload = {
        //     status : Nat;
        //     headers : [HttpHeader];
        //     body : [Nat8];
        // };

        //You need to decode that [Nat8] array that is the body into readable text.
        //To do this, you:
        //  1. Convert the [Nat8] into a Blob
        //  2. Use Blob.decodeUtf8() method to convert the Blob to a ?Text optional
        //  3. You use a switch to explicitly call out both cases of decoding the Blob into ?Text
        let response_body: Blob = Blob.fromArray(http_response.body);
        let decoded_text: Text = switch (Text.decodeUtf8(response_body)) {
            case (null) { "No value returned" };
            case (?y) { y };
        };

        // Parse the decoded_text to extract price and store it
        // Note: You'll need to add proper JSON parsing here
        // This is a simplified example
        let currentTime = Nat64.fromNat(Int.abs(Time.now()));
        storePriceData(currentTime, 0.0); // Replace 0.0 with actual parsed price

        //6. RETURN RESPONSE OF THE BODY
        //The API response will looks like this:

        // ("[[1682978460,5.714,5.718,5.714,5.714,243.5678]]")

        //Which can be formatted as this
        //  [
        //     [
        //         1682978460, <-- start/timestamp
        //         5.714, <-- low
        //         5.718, <-- high
        //         5.714, <-- open
        //         5.714, <-- close
        //         243.5678 <-- volume
        //     ],
        // ]
        decoded_text
    };

    //7. CREATE TRANSFORM FUNCTION
    public query func transform(raw : Types.TransformArgs) : async Types.CanisterHttpResponsePayload {
        let transformed : Types.CanisterHttpResponsePayload = {
            status = raw.response.status;
            body = raw.response.body;
            headers = [
                {
                    name = "Content-Security-Policy";
                    value = "default-src 'self'";
                },
                { name = "Referrer-Policy"; value = "strict-origin" },
                { name = "Permissions-Policy"; value = "geolocation=(self)" },
                {
                    name = "Strict-Transport-Security";
                    value = "max-age=63072000";
                },
                { name = "X-Frame-Options"; value = "DENY" },
                { name = "X-Content-Type-Options"; value = "nosniff" },
            ];
        };
        transformed;
    };

    // Add system function to start timer
    system func timer(setGlobalTimer : Nat64 -> ()) : async () {
        // Set up next timer call
        setGlobalTimer(FETCH_INTERVAL);
        // Fetch new price data
        ignore get_icp_usd_exchange();
    };
};