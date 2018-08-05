#include <boost/system/config.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/websocket.hpp>
#include <boost/beast/websocket/ssl.hpp>
#include <boost/asio/connect.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/ssl/stream.hpp>

#include <iostream>

using tcp = boost::asio::ip::tcp;               // from <boost/asio/ip/tcp.hpp>
namespace ssl = boost::asio::ssl;               // from <boost/asio/ssl.hpp>
namespace websocket = boost::beast::websocket;  // from <boost/beast/websocket.hpp>
namespace http = boost::beast::http;            // from <boost/beast/http.hpp>

class HttpsAsyncWebSocketTest : public std::enable_shared_from_this<HttpsAsyncWebSocketTest>
{
	tcp::resolver resolver;
	websocket::stream<ssl::stream<tcp::socket>> ws; // nextLayer = sslStream, next2 = tcp
	boost::beast::multi_buffer buffer;
	std::string const host;
	std::string const port;
	std::string const text;

	std::string const proxyHost;
	std::string const proxyPort;

	//http::request<http::string_body> req { http::verb::connect, "gjhgjhgjh", 11 };
	//http::parser<false, http::empty_body> p;

public:
	explicit HttpsAsyncWebSocketTest(boost::asio::io_context& ioc, ssl::context& ctx, char const* host, char const* port,
		const char * proxyHost, const char * proxyPort,
		char const* text)
		: resolver(ioc)
		, ws(ioc, ctx)
		, host(host)
		, port(port)
		, proxyHost(proxyHost)
		, proxyPort(proxyPort)
		, text(text)
//		, p(http::response<http::empty_body>())
	{
		//p.skip(true);
	}

	void Run();

private:
	void Resolve(const std::string& host, const std::string& port);
	void OnResolve(tcp::resolver::results_type results);
	
	void OnConnect();
	void OnProxyConnect();
	
	void Handshake();
	void OnSslHandshake();
	void OnHandshake();

	void Write();
	void OnWrite();

	void Read();
	void OnRead();
	
	void Close();
	void OnClose() const;

	static void Fail(boost::system::error_code ec, char const* what);
};

void HttpsAsyncWebSocketTest::Run()
{
	if (proxyHost.empty())
	{
		return Resolve(host, port);
	}
	return Resolve(proxyHost, proxyPort);
}

void HttpsAsyncWebSocketTest::Fail(boost::system::error_code ec, char const* what)
{
	std::cerr << what
		<< " : " << ec.message()
		<< " : " << ec.category().name() << "\n";
}

void HttpsAsyncWebSocketTest::Resolve(const std::string& host, const std::string& port)
{
	auto self(shared_from_this());
	resolver.async_resolve(host, port, [this, self](boost::system::error_code ec, tcp::resolver::results_type results)
	{
		if (ec) return Fail(ec, "resolve");
		OnResolve(results);
	});
}

void HttpsAsyncWebSocketTest::OnResolve(tcp::resolver::results_type results)
{
	auto self(shared_from_this());
	// tcp layer connect
	async_connect(ws.next_layer().next_layer(), results.begin(), results.end(), [this, self](boost::system::error_code ec, tcp::resolver::iterator i)
	{
		if (ec) return Fail(ec, "connect");
		OnConnect();
	});
}

void HttpsAsyncWebSocketTest::OnConnect()
{
	if (!proxyHost.empty())
	{
		std::string target = host + ":" + port;
		//auto req = std::make_unique<http::request<http::string_body>>(http::verb::connect, target, 11);
		//req->set(http::field::host, target);

		auto req = std::make_shared<http::request<http::string_body>>(http::verb::connect, target, 11);
		req->set(http::field::host, target);

		auto self(shared_from_this());

		// write ssl connect to tcp layer
		async_write(ws.next_layer().next_layer(), *req, [this, self, req](boost::system::error_code ec, std::size_t bytes_transferred)
		{
			if (ec) return Fail(ec, "proxyConnect");
			OnProxyConnect();
		});

		return;
	}
	Handshake();
}

void HttpsAsyncWebSocketTest::OnProxyConnect()
{
	auto self(shared_from_this());
		auto p = std::make_shared<http::parser<false, http::empty_body>>(http::response<http::empty_body>());
	p->skip(true);

	// read tcp connect response
	async_read(ws.next_layer().next_layer(), buffer, *p, [this, self, p](boost::system::error_code ec, std::size_t bytes_transferred)
	{
		if (ec) return Fail(ec, "proxyRead");
		std::cout << p->get() << std::endl;
		Handshake();
	});
}

void HttpsAsyncWebSocketTest::Handshake()
{
	auto self(shared_from_this());
	// ssl layer handshake
	ws.next_layer().async_handshake(ssl::stream_base::client, [this, self](boost::system::error_code ec)
	{
		if (ec) return Fail(ec, "ssl_handshake");
		OnSslHandshake();
	});
}

void HttpsAsyncWebSocketTest::OnSslHandshake()
{
	auto self(shared_from_this());
	// ws handshake
	ws.async_handshake(host, "/", [this, self](boost::system::error_code ec)
	{
		if (ec) return Fail(ec, "handshake");
		OnHandshake();
	});
}

void HttpsAsyncWebSocketTest::OnHandshake()
{
	Write();
}

void HttpsAsyncWebSocketTest::Write()
{
	auto self(shared_from_this());
	ws.async_write(boost::asio::buffer(text), [this, self](boost::system::error_code ec, std::size_t bytes_transferred)
	{
		if (ec) return Fail(ec, "write");
		OnWrite();
	});
}

void HttpsAsyncWebSocketTest::OnWrite()
{
	Read();
}

void HttpsAsyncWebSocketTest::Read()
{
	auto self(shared_from_this());
	ws.async_read(buffer, [this, self](boost::system::error_code ec, std::size_t bytes_transferred)
	{
		if (ec) return Fail(ec, "read");
		OnRead();
	});
}

void HttpsAsyncWebSocketTest::OnRead()
{
	// continual read call Read(); check close causes cleanish exit
	std::cout << buffers(buffer.data()) << std::endl;
	Close();

	// for continual reads neex external stop stimulus
	// buffer = boost::beast::multi_buffer {};
	// Read();
}

void HttpsAsyncWebSocketTest::Close()
{
	auto self(shared_from_this());
	ws.async_close(websocket::close_code::normal, [this, self](boost::system::error_code ec)
	{
		if (ec)
		{
			std::cout << ec.message() << std::endl; // error using proxy?, always ignore, just warn log
			//return Fail(ec, "close");
		}
		OnClose();
	});
}

void HttpsAsyncWebSocketTest::OnClose() const
{
	// std::cout << buffers(buffer.data()) << std::endl;
}

int main()
{
	auto const host = "echo.websocket.org";
	auto const port = "443";
	auto const path = "/";
	auto const text = "hello";

	// http=127.0.0.1:8888;https=127.0.0.1:8888
	auto const proxyHost = ""; // "127.0.0.1";
	auto const proxyPort = "8888";

	boost::asio::io_context ioc;
	ssl::context ctx { ssl::context::sslv23_client };
	//load_root_certificates(ctx);
	std::make_shared<HttpsAsyncWebSocketTest>(ioc, ctx, host, port, proxyHost, proxyPort, text)->Run();
	ioc.run();
}