defmodule Mithril.Web.RegistrationControllerTest do
  use EHealth.Web.ConnCase

  import Mox
  import EHealth.Guardian

  alias Ecto.UUID

  # For Mox lib. Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  defmodule SignatureExpect do
    defmacro __using__(_) do
      quote do
        expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
          content = signed_content |> Base.decode64!() |> Jason.decode!()

          first_name = content |> Map.get("first_name", "") |> String.upcase()

          data = %{
            "content" => content,
            "signed_content" => signed_content,
            "signatures" => [
              %{
                "is_valid" => true,
                "signer" => %{
                  "edrpou" => content["tax_id"],
                  "drfo" => content["tax_id"],
                  "surname" => content["last_name"],
                  "given_name" => "#{first_name} #{content["second_name"]}"
                },
                "validation_error_message" => ""
              }
            ]
          }

          {:ok, %{"data" => data}}
        end)
      end
    end
  end

  defmodule MithrilUserRoleExpect do
    defmacro __using__(_) do
      quote do
        expect(MithrilMock, :create_global_user_role, fn _user_id, params, _headers ->
          Enum.each(~w(role_id)a, fn key ->
            assert Map.has_key?(params, key),
                   "Mithril.create_user_role requires param `#{key}` in `#{inspect(params)}` "
          end)

          data = %{
            "id" => UUID.generate(),
            "scope" => "cabinet:read"
          }

          {:ok, %{"data" => data}}
        end)

        expect(MithrilMock, :create_access_token, fn _user_id, params, _headers ->
          Enum.each(~w(client_id scope)a, fn key ->
            assert Map.has_key?(params, key),
                   "Mithril.create_access_token requires param `#{key}` in `#{inspect(params)}`"
          end)

          assert "app:authorize" == params.scope

          data = %{
            "id" => UUID.generate(),
            "value" => "some_token_value"
          }

          {:ok, %{"data" => data}}
        end)
      end
    end
  end

  describe "send verification email" do
    test "invalid email", %{conn: conn} do
      assert "$.email" ==
               conn
               |> post(cabinet_auth_path(conn, :email_verification), %{email: "invalid@example"})
               |> json_response(422)
               |> get_in(~w(error invalid))
               |> hd()
               |> Map.get("entry")
    end

    test "no params", %{conn: conn} do
      assert "$.email" ==
               conn
               |> post(cabinet_auth_path(conn, :email_verification))
               |> json_response(422)
               |> get_in(~w(error invalid))
               |> hd()
               |> Map.get("entry")
    end

    test "user with passed email already exists", %{conn: conn} do
      email = "test@example.com"

      expect(MithrilMock, :search_user, fn %{email: "test@example.com"}, _headers ->
        {:ok, %{"data" => [%{"tax_id" => "23451234"}]}}
      end)

      assert [err] =
               conn
               |> post(cabinet_auth_path(conn, :email_verification), %{email: email})
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.email" == err["entry"]
      assert [rules] = err["rules"]
      assert "email_exists" == rules["rule"]
    end

    test "user with passed email already exists but tax_id is empty", %{conn: conn} do
      email = "success-new-user@example.com"

      expect(MithrilMock, :search_user, fn %{email: ^email}, _headers ->
        {:ok, %{"data" => [%{"tax_id" => ""}]}}
      end)

      expect(ManMock, :render_template, fn _id, _template_data ->
        {:ok, "<html></html>"}
      end)

      conn
      |> post(cabinet_auth_path(conn, :email_verification), %{email: email})
      |> json_response(200)
    end

    test "success", %{conn: conn} do
      email = "success-new-user@example.com"

      expect(MithrilMock, :search_user, 2, fn %{email: ^email}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(ManMock, :render_template, 2, fn _id, %{verification_code: jwt} ->
        {:ok, claims} = decode_and_verify(jwt)
        assert Map.has_key?(claims, "email")
        assert "success-new-user@example.com" == claims["email"]
        assert 3600 == claims["exp"] - claims["iat"]

        {:ok, "<html></html>"}
      end)

      # response contain urgent data with jwt token
      assert conn
             |> post(cabinet_auth_path(conn, :email_verification), %{email: email})
             |> json_response(200)
             |> get_in(~w(urgent token))

      # response DOES NOT contain urgent data with jwt token for disabled config
      System.put_env("SENSITIVE_DATA_IN_RESPONSE_ENABLED", "false")

      refute conn
             |> post(cabinet_auth_path(conn, :email_verification), %{email: email})
             |> json_response(200)
             |> get_in(~w(urgent token))

      on_exit(fn ->
        System.put_env("SENSITIVE_DATA_IN_RESPONSE_ENABLED", "true")
      end)
    end
  end

  describe "validate email jwt" do
    test "user with email do not exist", %{conn: conn} do
      expect(MithrilMock, :search_user, fn %{email: email}, _headers ->
        assert "info@example.com" == email
        {:ok, %{"data" => []}}
      end)

      email = "info@example.com"
      {:ok, jwt, _} = encode_and_sign(get_aud(:email_verification), %{email: email}, token_type: "access")

      assert token =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :email_validation))
               |> json_response(200)
               |> get_in(~w(data token))

      assert {:ok, claims} = decode_and_verify(token)
      assert Map.has_key?(claims, "email")
      assert email == claims["email"]
    end

    test "user with email exist but tax_id is empty", %{conn: conn} do
      expect(MithrilMock, :search_user, fn %{email: email}, _headers ->
        assert "info@example.com" == email
        {:ok, %{"data" => [%{"tax_id" => ""}]}}
      end)

      email = "info@example.com"
      {:ok, jwt, _} = encode_and_sign(get_aud(:email_verification), %{email: email}, token_type: "access")

      assert token =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :email_validation))
               |> json_response(200)
               |> get_in(~w(data token))

      assert {:ok, claims} = decode_and_verify(token)
      assert Map.has_key?(claims, "email")
      assert email == claims["email"]
    end

    test "user with email and not empty tax_id exists", %{conn: conn} do
      expect(MithrilMock, :search_user, fn %{email: email}, _headers ->
        assert "info@example.com" == email
        {:ok, %{"data" => [%{"tax_id" => "12345678"}]}}
      end)

      {:ok, jwt, _} = encode_and_sign(get_aud(:email_verification), %{email: "info@example.com"}, token_type: "access")

      assert [err] =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :email_validation))
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.email" == err["entry"]
      assert [rules] = err["rules"]
      assert "email_exists" == rules["rule"]
    end

    test "authorization header not send", %{conn: conn} do
      conn
      |> post(cabinet_auth_path(conn, :email_validation))
      |> json_response(401)
    end

    test "invalid JWT", %{conn: conn} do
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer some_stadsf")
      |> post(cabinet_auth_path(conn, :email_validation))
      |> json_response(401)
    end

    test "invalid JWT type", %{conn: conn} do
      {:ok, jwt, _} =
        encode_and_sign(get_aud(:email_verification), %{email: "email@example.com"}, token_type: "refresh")

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :email_validation))
      |> json_response(401)
    end

    test "invalid JWT aud", %{conn: conn} do
      {:ok, jwt, _} = encode_and_sign(get_aud(:registration), %{email: "email@example.com"}, token_type: "access")

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :email_validation))
      |> json_response(401)
    end

    test "invalid JWT claim", %{conn: conn} do
      jwt =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJlbWFpbC12ZXJpZmljYXRpb24iLCJleHAiOjE4Mzc4NDEwNDIs" <>
          "ImlhdCI6MTUyMzM0NTA0MiwiaXNzIjoiRUhlYWx0aCIsImp0aSI6ImM4MDgzNmEzLTk0OWUtNGZjYi1hMjBiLTQ5MjM4OWN" <>
          "mYTdkZCIsIm5iZiI6MTUyMzM0NTA0MSwic3ViIjoidGVzdCIsInRlc3QiOiJ0ZXN0QGV4YW1wbGUuY29tIiwidHlwIjoiYW" <>
          "NjZXNzIn0.G-oRfD52cs42yQXfc2gyB-pnQdx9WZczBirhBhxeFGegiJtdYBTAj7ViXaHLRfJdJ9-9ESgJa_d7WruGbCC2HA"

      assert {:ok, claims} = decode_and_verify(jwt)
      refute Map.has_key?(claims, "email")

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :email_validation))
      |> json_response(401)
    end

    test "JWT expired", %{conn: conn} do
      {:ok, jwt, _} =
        encode_and_sign(
          get_aud(:email_verification),
          %{email: "email@example.com", exp: 1_524_210_044},
          token_type: "access"
        )

      assert {:error, :token_expired} = decode_and_verify(jwt)

      assert "jwt_expired" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :email_validation))
               |> json_response(401)
               |> get_in(~w(error type))
    end
  end

  describe "success patient registration" do
    setup %{conn: conn} do
      use SignatureExpect
      use MithrilUserRoleExpect

      params = %{
        otp: "1234",
        password: "pAs$w0rd",
        signed_content: "test/data/cabinet/patient.json" |> File.read!() |> Base.encode64(),
        signed_content_encoding: "base64"
      }

      {:ok, jwt, _} = encode_and_sign(get_aud(:registration), %{email: "email@example.com"})
      %{conn: Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> jwt), params: params}
    end

    test "create new person and user", %{conn: conn, params: params} do
      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MPIMock, :create_or_update_person!, fn params, headers ->
        refute Map.has_key?(params, "id")
        assert Map.has_key?(params, "patient_signed")
        assert Enum.member?(headers, {"x-consumer-id", "4261eacf-8008-4e62-899f-de1e2f7065f0"})
        {:ok, %{"data" => Map.put(params, "id", UUID.generate())}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :create_user, fn params, _headers ->
        Enum.each(~w(otp tax_id email password 2fa_enable factor), fn key ->
          assert Map.has_key?(params, key)
        end)

        data =
          params
          |> Map.put("id", UUID.generate())
          |> Map.delete("password")

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :change_user, fn id, params, _headers ->
        assert Map.has_key?(params, "person_id")

        {:ok, %{"data" => Map.put(params, "id", id)}}
      end)


      uaddresses_mock_expect()

      conn
      |> post(cabinet_auth_path(conn, :registration, params))
      |> json_response(201)

      # |> assert_show_response_schema("cabinet")
    end

    test "create new user and update MPI person", %{conn: conn, params: params} do
      person_id = UUID.generate()

      expect(MPIMock, :search, fn params, _headers ->
        Enum.each(~w(tax_id birth_date status), fn key ->
          assert Map.has_key?(params, key)
        end)

        assert "3126509816" == params["tax_id"]
        assert "active" == params["status"]

        {:ok, %{"data" => [%{"id" => person_id}]}}
      end)

      expect(MPIMock, :update_person, fn ^person_id, params, _headers ->
        assert Map.has_key?(params, "patient_signed")
        {:ok, %{"data" => Map.put(params, "id", person_id)}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :create_user, fn params, _headers ->
        Enum.each(~w(otp tax_id email password 2fa_enable factor), fn key ->
          assert Map.has_key?(params, key)
        end)

        data =
          params
          |> Map.put("id", UUID.generate())
          |> Map.delete("password")

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :change_user, fn id, params, _headers ->
        assert Map.has_key?(params, "person_id")

        {:ok, %{"data" => Map.put(params, "id", id)}}
      end)

      uaddresses_mock_expect()

      conn
      |> post(cabinet_auth_path(conn, :registration, params))
      |> json_response(201)

      # |> assert_show_response_schema("cabinet")
    end

    @tag :pending
    test "update user and create new MPI person", %{conn: conn, params: params} do
      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MPIMock, :create_or_update_person!, fn params, _headers ->
        refute Map.has_key?(params, "id")
        assert Map.has_key?(params, "patient_signed")

        data =
          :person
          |> string_params_for(params)
          |> Map.put("id", UUID.generate())

        {:ok, %{"data" => data}}
      end)

      user_id = UUID.generate()

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => [%{"id" => user_id, "tax_id" => ""}]}}
      end)

      expect(MithrilMock, :change_user, fn ^user_id, params, _headers ->
        assert Map.has_key?(params, "tax_id")
        assert Map.has_key?(params, "email")
        assert Map.has_key?(params, "password")

        data =
          params
          |> Map.put("id", user_id)
          |> Map.delete("password")

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :change_user, fn id, params, _headers ->
        assert Map.has_key?(params, "person_id")

        {:ok, %{"data" => Map.put(params, "id", id)}}
      end)


      uaddresses_mock_expect()

      conn
      |> post(cabinet_auth_path(conn, :registration, params))
      |> json_response(201)
      |> assert_json_schema("specs/json_schemas/cabinet/cabinet_registration_show_response.json")
    end

    test "update user and update MPI person", %{conn: conn, params: params} do
      person_id = UUID.generate()

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => [%{"id" => person_id}]}}
      end)

      expect(MPIMock, :update_person, fn ^person_id, params, headers ->
        assert Map.has_key?(params, "patient_signed")
        assert Enum.member?(headers, {"x-consumer-id", "4261eacf-8008-4e62-899f-de1e2f7065f0"})
        {:ok, %{"data" => Map.put(params, "id", person_id)}}
      end)

      user_id = UUID.generate()

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => [%{"id" => user_id, "tax_id" => ""}]}}
      end)

      expect(MithrilMock, :change_user, fn ^user_id, params, _headers ->
        assert Map.has_key?(params, "tax_id")
        assert Map.has_key?(params, "email")
        assert Map.has_key?(params, "password")

        data =
          params
          |> Map.put("id", user_id)
          |> Map.delete("password")

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :change_user, fn id, params, _headers ->
        assert Map.has_key?(params, "person_id")

        {:ok, %{"data" => Map.put(params, "id", id)}}
      end)


      uaddresses_mock_expect()

      conn
      |> post(cabinet_auth_path(conn, :registration, params))
      |> json_response(201)

      # |> assert_show_response_schema("cabinet")
    end
  end

  describe "invalid patient registration" do
    setup %{conn: conn} do
      params = %{
        otp: "1234",
        password: "pAs$w0rd",
        signed_content: "test/data/cabinet/patient.json" |> File.read!() |> Base.encode64(),
        signed_content_encoding: "base64"
      }

      {:ok, jwt, _} = encode_and_sign(get_aud(:registration), %{email: "email@example.com"})

      %{conn: conn, params: params, jwt: jwt}
    end

    test "user exists with tax_id", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => [%{"tax_id" => "1234567890"}]}}
      end)

      uaddresses_mock_expect()

      assert "tax_id_exists" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "user blocked", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => [%{"tax_id" => "1234567890", "is_blocked" => true}]}}
      end)

      uaddresses_mock_expect()

      assert "User blocked" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(401)
               |> get_in(~w(error message))
    end

    test "invalid adresses types", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      signed_content = "test/data/cabinet/patient-invalid-addresses-types.json" |> File.read!() |> Base.encode64()
      params = Map.put(params, :signed_content, signed_content)

      assert "Addresses with types REGISTRATION, RESIDENCE should be present" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(422)
               |> get_in(~w(error message))
    end

    test "MPI persons duplicated", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => [%{"id" => UUID.generate()}, %{"id" => UUID.generate()}]}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => []}}
      end)

      uaddresses_mock_expect()

      assert "person_duplicated" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "different last_name in signed content and DS", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => content["tax_id"],
                "surname" => "Шевченко",
                "given_name" => content["first_name"] <> " " <> content["second_name"]
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      uaddresses_mock_expect()

      assert "Input last_name doesn't match name from DS" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error message))
    end

    test "no surname in Signer from DS", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => content["tax_id"],
                "given_name" => content["first_name"] <> " " <> content["second_name"]
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      uaddresses_mock_expect()

      assert "Input last_name doesn't match name from DS" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error message))
    end

    test "different first_name in signed content and DS", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => content["tax_id"],
                "surname" => content["last_name"],
                "given_name" => "Сара Коннор"
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      uaddresses_mock_expect()

      assert "Input first_name doesn't match name from DS" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error message))
    end

    test "no given_name in Signer from DS", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => content["tax_id"],
                "surname" => content["last_name"]
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      uaddresses_mock_expect()

      assert "signer_empty_given_name" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "different email in signed content and JWT", %{conn: conn, params: params} do
      use SignatureExpect
      {:ok, jwt, _} = encode_and_sign(get_aud(:registration), %{email: "not-matched@example.com"})

      uaddresses_mock_expect()

      assert "Email in signed content is incorrect" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error message))
    end

    test "DS cannot decode signed content", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn _signed_content, "base64", _headers ->
        err_data = %{
          "error" => %{
            "invalid" => [
              %{
                "entry" => "$.signed_content",
                "entry_type" => "json_data_property",
                "rules" => [
                  %{
                    "description" => "Not a base64 string",
                    "params" => [],
                    "rule" => "invalid"
                  }
                ]
              }
            ],
            "message" =>
              "Validation failed. You can find validators description at our API Manifest:" <>
                " http://docs.apimanifest.apiary.io/#introduction/interacting-with-api/errors.",
            "type" => "validation_failed"
          },
          "meta" => %{
            "code" => 422,
            "request_id" => "2kmaguf9ec791885t40008s2",
            "type" => "object",
            "url" => "http://www.example.com/digital_signatures"
          }
        }

        {:error, %{"data" => err_data, "meta" => %{"code" => 422, "type" => "list"}}}
      end)

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :registration), params)
      |> json_response(422)
    end

    test "different tax_id in signed content and digital signature", %{conn: conn, params: params, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()
        assert Map.has_key?(content, "tax_id")

        data = %{
          "content" => content,
          "signed_content" => signed_content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => "002233445566"
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      uaddresses_mock_expect()

      assert "Registration person and person that sign should be the same" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration), params)
               |> json_response(409)
               |> get_in(~w(error message))
    end

    test "invalid signed_content format", %{conn: conn, params: params, jwt: jwt} do
      params = Map.put(params, :signed_content, "some string")

      assert [err] =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration, params))
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.signed_content" == err["entry"]
    end

    test "JWT not set", %{conn: conn, params: params} do
      conn
      |> post(cabinet_auth_path(conn, :registration, params))
      |> json_response(401)
    end

    test "invalid JWT aud", %{conn: conn} do
      {:ok, jwt, _} = encode_and_sign(get_aud(:email_verification), %{email: "email@example.com"}, token_type: "access")

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :registration))
      |> json_response(401)
    end

    test "invalid person data", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      signed_content =
        %{
          "birth_date" => "today",
          "tax_id" => "1112223344",
          "email" => "email@example.com"
        }
        |> Jason.encode!()
        |> Base.encode64()

      err =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
        |> post(cabinet_auth_path(conn, :registration, Map.put(params, :signed_content, signed_content)))
        |> json_response(422)
        |> get_in(~w(error invalid))

      assert "$.birth_date" == hd(err)["entry"]
    end

    test "422 response code on MPI", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :create_user, fn id, params, _headers ->
        assert Map.has_key?(params, "person_id")

        {:ok, %{"data" => Map.put(params, "id", id)}}
      end)

      expect(MithrilMock, :delete_user, fn id, _headers ->
        {:ok, %{"data" => ""}}
      end)

      expect(MPIMock, :create_or_update_person!, fn _params, _headers ->
        {:error,
         %{
           "error" => %{
             "invalid" => [
               %{
                 "entry" => "$.email",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "invalid email format",
                     "params" => [],
                     "rule" => "format"
                   }
                 ]
               }
             ],
             "message" => "Validation failed.",
             "type" => "validation_failed"
           },
           "meta" => %{
             "code" => 422
           }
         }}
      end)

      uaddresses_mock_expect()

      assert [err] =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration, params))
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.email" == err["entry"]
    end

    test "invalid OTP for user factor", %{conn: conn, params: params, jwt: jwt} do
      use SignatureExpect

      expect(MPIMock, :search, fn %{"tax_id" => "3126509816", "birth_date" => _}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn %{email: "email@example.com"}, _headers ->
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :create_user, fn _params, _headers ->
        {:error,
         %{
           "error" => %{
             "invalid" => [
               %{
                 "entry" => "$.otp",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "invalid code",
                     "params" => [],
                     "rule" => "invalid"
                   }
                 ]
               }
             ],
             "message" => "Validation failed.",
             "type" => "validation_failed"
           },
           "meta" => %{
             "code" => 422
           }
         }}
      end)

      uaddresses_mock_expect()

      assert [err] =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :registration, params))
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.otp" == err["entry"]
    end
  end

  describe "search user" do
    setup %{conn: conn} do
      {:ok, jwt, _} = encode_and_sign(get_aud(:registration), %{email: "email@example.com"})

      params = %{
        signed_content: sign_content(%{tax_id: "1234567890"}),
        signed_content_encoding: "base64"
      }

      %{conn: conn, jwt: jwt, params: params}
    end

    test "jwt not set", %{conn: conn, params: params} do
      conn
      |> post(cabinet_auth_path(conn, :search_user), params)
      |> json_response(401)
    end

    test "by tax_id not found", %{conn: conn, jwt: jwt, params: params} do
      use SignatureExpect

      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :email)
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :tax_id)
        assert "1234567890" == params.tax_id
        {:ok, %{"data" => []}}
      end)

      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :search_user, params))
      |> json_response(200)
    end

    test "Empty drfo in Signer from DS", %{conn: conn, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "drfo" => "",
                "surname" => content["last_name"]
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :email)
        {:ok, %{"data" => []}}
      end)

      params = %{
        signed_content: sign_content(%{tax_id: ""}),
        signed_content_encoding: "base64"
      }

      assert "drfo_not_present" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :search_user), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "No drfo in Signer from DS", %{conn: conn, jwt: jwt} do
      expect(SignatureMock, :decode_and_validate, fn signed_content, "base64", _headers ->
        content = signed_content |> Base.decode64!() |> Jason.decode!()

        data = %{
          "content" => content,
          "signatures" => [
            %{
              "is_valid" => true,
              "signer" => %{
                "surname" => content["last_name"]
              },
              "validation_error_message" => ""
            }
          ]
        }

        {:ok, %{"data" => data}}
      end)

      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :email)
        {:ok, %{"data" => []}}
      end)

      params = %{
        signed_content: sign_content(%{tax_id: ""}),
        signed_content_encoding: "base64"
      }

      assert "drfo_not_present" ==
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :search_user), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "by tax_id found", %{conn: conn, jwt: jwt, params: params} do
      use SignatureExpect

      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :email)
        {:ok, %{"data" => []}}
      end)

      expect(MithrilMock, :search_user, fn %{tax_id: "1234567890"}, _headers ->
        {:ok, %{"data" => [%{"id" => 1}]}}
      end)

      assert "tax_id_exists" =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :search_user), params)
               |> json_response(409)
               |> get_in(~w(error type))
    end

    test "user with email already exists", %{conn: conn, jwt: jwt, params: params} do
      expect(MithrilMock, :search_user, fn params, _headers ->
        assert Map.has_key?(params, :email)
        {:ok, %{"data" => [%{"id" => UUID.generate(), "tax_id" => "12342345"}]}}
      end)

      assert [err] =
               conn
               |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
               |> post(cabinet_auth_path(conn, :search_user), params)
               |> json_response(422)
               |> get_in(~w(error invalid))

      assert "$.email" == err["entry"]
      assert [rules] = err["rules"]
      assert "email_exists" == rules["rule"]
    end

    test "invalid params", %{conn: conn, jwt: jwt} do
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> jwt)
      |> post(cabinet_auth_path(conn, :search_user), %{tax_id: "1234567890"})
      |> json_response(422)
    end
  end

  defp sign_content(content) do
    content
    |> Jason.encode!()
    |> Base.encode64()
  end

  defp uaddresses_mock_expect do
    expect(UAddressesMock, :validate_addresses, fn _, _headers ->
      {:ok, %{"data" => %{}}}
    end)
  end
end
