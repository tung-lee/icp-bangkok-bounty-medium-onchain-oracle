import Blob "mo:base/Blob";
import ExperimentalCycles "mo:base/ExperimentalCycles";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Timer "mo:base/Timer";
import Time "mo:base/Time";
import Types "Types";
import Debug "mo:base/Debug";
import Error "mo:base/Error";

actor {
  type CryptoQuote = {
    rawJson: Text;
    captureTime: Int;
  };

  private stable var quoteArchive: [CryptoQuote] = [];
  private stable var monitorRunning: Bool = false;
  private stable var latestFetchTime: Int = 0;
  private let API_CYCLE_AMOUNT = 35_000_000_000;
  private let REFRESH_SECONDS = 1800; // 30 minutes
  private let SYSTEM_CANISTER = "aaaaa-aa";

  system func heartbeat() : async () {
    if (not monitorRunning) {
      Debug.print("Starting quote monitor");
      monitorRunning := true;
      ignore await fetchCryptoQuote();
    };
  };

  public query func monitorStatus() : async {
    isRunning: Bool;
    lastFetch: Int;
    archiveLength: Nat;
    availableCycles: Nat;
  } {
    {
      isRunning = monitorRunning;
      lastFetch = latestFetchTime;
      archiveLength = quoteArchive.size();
      availableCycles = ExperimentalCycles.balance();
    }
  };

  public shared func triggerManualFetch() : async Text {
    Debug.print("Manual fetch initiated");
    await fetchCryptoQuote()
  };

  public query func getQuoteArchive() : async [CryptoQuote] {
    quoteArchive;
  };

  public query func transform(input : Types.TransformArgs) : async Types.CanisterHttpResponsePayload {
    {
      status = input.response.status;
      body = input.response.body;
      headers = [
        { name = "Content-Security-Policy"; value = "default-src 'self'" },
        { name = "Referrer-Policy"; value = "strict-origin" },
        { name = "Permissions-Policy"; value = "geolocation=(self)" },
        { name = "Strict-Transport-Security"; value = "max-age=63072000" },
        { name = "X-Frame-Options"; value = "DENY" },
        { name = "X-Content-Type-Options"; value = "nosniff" },
      ];
    };
  };

  private func fetchCryptoQuote() : async Text {
    Debug.print("Initiating quote fetch");
    Debug.print("Cycle balance: " # debug_show(ExperimentalCycles.balance()));
    
    let systemCanister : Types.ExternalService = actor(SYSTEM_CANISTER);
    let apiEndpoint = "api.coinbase.com";
    
    let requestConfig : Types.HttpRequestArgs = {
      url = "https://" # apiEndpoint # "/v2/prices/ICP-USD/spot";
      max_response_bytes = null;
      headers = [
        { name = "Host"; value = apiEndpoint # ":443" },
        { name = "User-Agent"; value = "crypto_quote_monitor" },
      ];
      body = null;
      method = #get;
      transform = ?{
        function = transform;
        context = Blob.fromArray([]);
      };
    };

    ExperimentalCycles.add<system>(API_CYCLE_AMOUNT);
    
    try {
      let apiResponse = await systemCanister.http_request(requestConfig);
      
      let quoteData = switch (Text.decodeUtf8(Blob.fromArray(apiResponse.body))) {
        case null { 
          Debug.print("Quote decoding failed");
          throw Error.reject("Unable to decode quote data") 
        };
        case (?value) {
          quoteArchive := Array.append<CryptoQuote>(
            quoteArchive, 
            [{
              rawJson = value;
              captureTime = Time.now();
            }]
          );
          latestFetchTime := Time.now();
          value;
        };
      };
      quoteData;
    } catch (e) {
      let errorMsg = Error.message(e);
      Debug.print("API request failed: " # errorMsg);
      throw Error.reject("Failed to fetch quote: " # errorMsg);
    };
  };

  private func scheduleNextFetch(): async() {
    Debug.print("Executing scheduled fetch");
    ignore fetchCryptoQuote();
  };

  ignore Timer.recurringTimer<system>(#seconds REFRESH_SECONDS, scheduleNextFetch);
};