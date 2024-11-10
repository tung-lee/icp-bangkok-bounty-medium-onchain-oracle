import { useState, useEffect } from 'react';
import { send_http_get_motoko_backend } from 'declarations/send_http_get_motoko_backend';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
} from 'chart.js';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

function App() {
  const [exchangeRate, setExchangeRate] = useState('Loading...');
  const [priceHistory, setPriceHistory] = useState([]);

  const chartOptions = {
    responsive: true,
    plugins: {
      legend: {
        position: 'top',
      },
      title: {
        display: true,
        text: 'ICP Price History',
      },
    },
  };

  const chartData = {
    labels: priceHistory.map(([timestamp]) => 
      new Date(Number(timestamp) / 1_000_000).toLocaleString()
    ),
    datasets: [
      {
        label: 'ICP Price (USD)',
        data: priceHistory.map(([, price]) => price),
        borderColor: 'rgb(75, 192, 192)',
        tension: 0.1,
      },
    ],
  };

  // Function to fetch current exchange rate
  const fetchExchangeRate = async () => {
    try {
      const response = await send_http_get_motoko_backend.triggerManualFetch();
      const data = JSON.parse(response);
      const price = data.data.amount;
      setExchangeRate(`$${price}`);
    } catch (error) {
      setExchangeRate('Error fetching rate');
      console.error(error);
    }
  };

  // Function to fetch price history
  const fetchPriceHistory = async () => {
    try {
      const archive = await send_http_get_motoko_backend.getQuoteArchive();
      const history = archive.map(entry => {
        const data = JSON.parse(entry.rawJson);
        return [entry.captureTime, Number(data.data.amount)];
      });
      setPriceHistory(history);
    } catch (error) {
      console.error('Error fetching price history:', error);
    }
  };

  // Fetch data on component mount and every minute
  useEffect(() => {
    fetchExchangeRate();
    fetchPriceHistory();
    
    const interval = setInterval(() => {
      fetchExchangeRate();
      fetchPriceHistory();
    }, 60000); // Update every minute

    return () => clearInterval(interval);
  }, []);

  return (
    <main>
      <img src="/logo2.svg" alt="DFINITY logo" />
      <h1>ICP-USD Exchange Rate</h1>
      
      <div className="exchange-rate">
        <h2>Current Rate: {exchangeRate}</h2>
        <button onClick={fetchExchangeRate}>Refresh Rate</button>
      </div>

      <div className="price-history">
        <h2>Price History</h2>
        <div style={{ maxWidth: '800px', margin: '20px auto' }}>
          <Line options={chartOptions} data={chartData} />
        </div>
        <table>
          <thead>
            <tr>
              <th>Timestamp</th>
              <th>Price (USD)</th>
            </tr>
          </thead>
          <tbody>
            {priceHistory.map(([timestamp, price]) => (
              <tr key={timestamp}>
                <td>{new Date(Number(timestamp) / 1_000_000).toLocaleString()}</td>
                <td>${price}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}

export default App;
