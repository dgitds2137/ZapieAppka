from kivy.lang import Builder
from kivymd.app import MDApp
from kivy.core.window import Window
import httpx
import os
import base64
import json
import os
from kivy.utils import platform
from kivymd.uix.menu import MDDropdownMenu
import base64
import requests
from kivy.uix.image import AsyncImage
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.metrics import dp
from kivy.uix.relativelayout import RelativeLayout
from kivymd.uix.button import MDIconButton
from kivy.metrics import dp
from kivy.uix.floatlayout import FloatLayout
from kivy.metrics import dp
# Kivy podstawowe layouty i widgety
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.floatlayout import FloatLayout   # jeśli używasz overlay na obrazku
from kivy.uix.label import Label
from kivy.uix.image import AsyncImage
import json, os
from kivy.utils import platform
# Kivy narzędzia
from kivy.metrics import dp
from kivy.graphics import Color, Line
import jwt
# KivyMD (serduszko, styl Material Design)
from kivymd.uix.button import MDIconButton
from kivy.graphics import Color, RoundedRectangle
from kivy.uix.behaviors import ButtonBehavior
from google_auth_oauthlib.flow import InstalledAppFlow
from kivy.properties import ObjectProperty
from kivymd.uix.screen import MDScreen
from kivy.core.window import Window
from kivymd.app import MDApp
from kivymd.uix.appbar import MDTopAppBar
from kivymd.uix.screen import MDScreen


Window.size = (600, 980)
Window.minimum_width = 600
Window.minimum_height = 980

class PositionTile(ButtonBehavior, BoxLayout):
    pass

class PositionScreen(MDScreen):
    pos_id = 0
    pos_data = ObjectProperty(None)  # tu trzymamy cały JSON

class OrderSummaryScreen(MDScreen):
    pass

class RegisterScreen(MDScreen):
    pass

class LoginScreen(MDScreen):
    pass

class DashboardScreen(MDScreen):
    pass
from kivymd.uix.screen import MDScreen
from kivy.lang import Builder
import httpx


class DashboardScreen(MDScreen):

    def on_enter(self):
        self.load_products()

    def load_products(self):
        try:
            resp = httpx.get("http://127.0.0.1:8000/positions")

            if resp.status_code == 200:
                products = resp.json()
                self.show_products(products)
            else:
                print("Błąd pobierania pozycji:", resp.status_code, resp.text)

        except Exception as e:
            print("Błąd ładowania produktów:", e)

    def show_products(self, products):
        grid = self.ids.products_grid
        grid.clear_widgets()

        for p in products:
            card = ProductCard(
                title=str(p.get("name", "")),
                desc=str(p.get("description", "")),
                image=str(p.get("image_url", "")),
            )
            grid.add_widget(card)

from kivy.properties import StringProperty
from kivymd.uix.card import MDCard
from kivymd.uix.screen import MDScreen
import httpx

class ProductCard(MDCard):
    title = StringProperty("")
    desc = StringProperty("")
    image = StringProperty("")

class DeliveryScreen(MDScreen):
    pass

class CartScreen(MDScreen):
    pass

class OrdersHistoryScreen(MDScreen):
    pass

class AddressScreen(MDScreen):
    pass

class PositionTile(ButtonBehavior, BoxLayout):
    pass
    
class PositionScreen(MDScreen):
    pos_id = 0
    pos_data = ObjectProperty(None)  # tu trzymamy cały JSON

class OrderSummaryScreen(MDScreen):
    pass

class FastFoodApp(MDApp):
    SECRET_KEY = "supersecret"   # ten sam klucz co w backendzie
    ALGORITHM = "HS256"
    CART = []
    LAST_ORDERS = []
    FAVORITES = []
    USER_PROFILE = None

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # --- STATE ---
        self.token = None
        self.user_email = None
        self.user_profile = None

        self.menu_cache = {}          # {id: {name, price, ...}}
        self.cart = {}                # {menu_position_id: qty}
        self.selected_address = None  # address_id
        self.order_type = "pickup"    # "pickup" / "delivery"

    def go_back(self):
        # wraca do dashboard albo innego ekranu
        self.root.current = "dashboard"
        
    def set_delivery(self, method):
        if method == "local":
            self.delivery_method = "local"
        else:
            self.delivery_method = "delivery"
        print("Wybrana metoda dostawy:", self.delivery_method)

    # ---------------------------------------------------------
    # ADDRESSES
    # ---------------------------------------------------------
    def load_addresses(self):
        r = requests.get(f"{API}/addresses")
        if r.status_code == 200:
            return r.json()
        return []

    def set_selected_address(self, address_id):
        self.selected_address = address_id
    # ---------------------------------------------------------
    # ORDER FLOW
    # ---------------------------------------------------------
    def set_delivery(self, method):
        self.order_type = "pickup" if method == "local" else "delivery"
        print("Wybrana metoda:", self.order_type)

    def create_order(self, notes=None):
        payload = {
            "order_type": self.order_type,
            "address_id": self.selected_address,
            "notes": notes,
        }
        r = requests.post(f"{API}/orders", json=payload)
        if r.status_code == 201:
            return r.json()
        print("Błąd tworzenia zamówienia:", r.text)
        return None

    def add_items_to_order(self, order_id):
        for pos_id, qty in self.cart.items():
            payload = {"menu_position_id": pos_id, "quantity": qty}
            r = requests.post(f"{API}/orders/{order_id}/items", json=payload)
            if r.status_code not in (200, 201):
                print("Błąd dodawania pozycji:", r.text)

    def submit_order(self, order_id):
        r = requests.post(f"{API}/orders/{order_id}/submit")
        if r.status_code == 200:
            return True
        print("Błąd submit:", r.text)
        return False

    def make_full_order(self, notes=None):
        order = self.create_order(notes)
        if not order:
            return None

        order_id = order["id"]
        self.add_items_to_order(order_id)
        ok = self.submit_order(order_id)

        if ok:
            self.cart.clear()
            return order_id
        return None
     # ---------------------------------------------------------
    # ORDER HISTORY
    # ---------------------------------------------------------
    def load_last_orders(self):
        r = requests.get(f"{API}/orders/my")
        if r.status_code == 200:
            return r.json()
        return []

    def reorder(self, order_id):
        r = requests.post(f"{API}/orders/{order_id}/reorder")
        if r.status_code == 200:
            return r.json()
        print("Błąd reorder:", r.text)
        return None
    # ---------------------------------------------------------
    # CART
    # ---------------------------------------------------------
    def add_to_cart(self, pos_id: int):
        self.cart[pos_id] = self.cart.get(pos_id, 0) + 1

    def change_cart_qty(self, pos_id: int, delta: int):
        if pos_id not in self.cart:
            return
        self.cart[pos_id] += delta
        if self.cart[pos_id] <= 0:
            del self.cart[pos_id]
    # ---------------------------------------------------------
    # NAVIGATION
    # ---------------------------------------------------------
    def go_back(self):
        self.root.current = "dashboard"

    def go_to(self, screen_name):
        self.root.current = screen_name

    # ---------------------------------------------------------
    # UI HOOKS (dashboard, menu, etc.)
    # ---------------------------------------------------------
    def show_positions(self, positions):
        # tutaj wstawiasz logikę do dashboardu
        # np. wypełnianie MDList
        pass
    
    def build(self):
        root = Builder.load_file("fastfood.kv")

        token = self.load_token()
        print("token", token)

        if token:
            root.current = "dashboard"
        else:
            root.current = "login"

        print("BUILD")
        return root

    def on_start(self):
        try:
            response = requests.get("http://127.0.0.1:8000/positions")
            if response.status_code == 200:
                positions = response.json()
                self.show_positions(positions)
            else:
                print("Błąd pobierania pozycji:", response.text)

            email = self.get_user_email()
            self.load_user_profile(email)
        except Exception as e:
            print("Błąd sieci:", e)

    def load_last_orders(self):
        pass
        # # przykładowe pobranie z backendu
        # orders = self.api_get_last_orders()
 
        # screen = self.root.get_screen("dashboard")

        # if orders and len(orders) > 0:
        #     # pokaż label i scrollview
        #     screen.ids.l_last_orders_box.opacity = 1
        #     screen.ids.l_last_orders_box.disabled = False
        #     screen.ids.sv_last_orders_box.opacity = 1
        #     screen.ids.sv_last_orders_box.disabled = False

        #     # wyczyść stare kafelki
        #     screen.ids.last_orders_box.clear_widgets()

        #     # dodaj nowe kafelki
        #     for order in orders:
        #         screen.ids.last_orders_box.add_widget(
        #             MDLabel(text=f"#{order['id']} - {order['status']}")
        #         )
        # else:
        #     # ukryj sekcję jeśli brak zamówień
        #     screen.ids.l_last_orders_box.opacity = 0
        #     screen.ids.l_last_orders_box.disabled = True
        #     screen.ids.sv_last_orders_box.opacity = 0
        #     screen.ids.sv_last_orders_box.disabled = True
    def handle_delivery(self):
        # przejście na ekran formularza
        self.root.current = "delivery"

        # wczytaj adres użytkownika z backendu
        try:
            response = requests.get("http://127.0.0.1:8000/user/address")
            if response.status_code == 200:
                addr = response.json()
                delivery_screen = self.root.get_screen("delivery")
                delivery_screen.ids.street.text = addr.get("street", "")
                delivery_screen.ids.city.text = addr.get("city", "")
                delivery_screen.ids.postal.text = addr.get("postal", "")
                delivery_screen.ids.phone.text = addr.get("phone", "")
            else:
                print("Brak adresu w bazie:", response.text)
        except Exception as e:
            print("Błąd sieci:", e)

    # ---------------------------------------------------------
    # MENU
    # ---------------------------------------------------------
    def load_menu(self):
        r = requests.get(f"{API}/positions")
        if r.status_code == 200:
            positions = r.json()
            for pos in positions:
                self.menu_cache[pos["id"]] = pos

            # wyświetl na dashboardzie
            self.show_positions(positions)
        else:
            print("Błąd pobierania menu:", r.text)
    def open_position(self, pos):
        print(pos)
        self.current_position = pos
        screen = self.root.get_screen("position")
        screen.pos_id = pos["position_id"]
        screen.position = pos
        screen.ids.pos_image.source = pos["photo_url"]
        screen.ids.pos_title.text = pos["name"]
        screen.ids.pos_desc.text = pos["description"]
        self.root.current = "position"
        # self.on_start()

    def get_storage_path(self):
        if platform == "android":
            from android.storage import app_storage_path
            return app_storage_path()
        elif platform == "ios":
            from plyer import storagepath
            return storagepath.get_documents_dir()
        else:
            return os.getcwd()
    def load_user_profile(self, email):
        response = requests.get(
                f"http://localhost:8000/get_user/{email}"
            )

        if response.status_code == 200:
            data = response.json()
            self.LAST_ORDERS = data["last_orders"]
            self.USER_PROFILE = data
            self.LAST_ORDERS = data.get("last_orders", [])
            self.show_last_orders()

    def save_token(self, id_token: str, access_token: str):
        path = self.get_storage_path()
        file_path = os.path.join(path, "loginlog.json")
        with open(file_path, "w") as f:
            json.dump({
                "id_token": id_token,
                "access_token": access_token
            }, f)
        print("Token zapisany w:", file_path)

    def get_user_email(self):
        """Odczytuje token Google z pliku JSON."""
        path = self.get_storage_path()
        file_path = os.path.join(path, "loginlog.json")
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                payload = jwt.decode(json.load(f).get("id_token"), options={"verify_signature": False})
                email = payload.get("email")
                return email 
        return None

    def load_token(self):
        """Odczytuje token Google z pliku JSON."""
        path = self.get_storage_path()
        file_path = os.path.join(path, "loginlog.json")
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return json.load(f).get("access_token")
        return None
    
    def google_login(self):
        try:
            flow = InstalledAppFlow.from_client_secrets_file(
                "client_secret.json",
                scopes=[
                    "openid",
                    "https://www.googleapis.com/auth/userinfo.email",
                    "https://www.googleapis.com/auth/userinfo.profile"
                ]
            )
            creds = flow.run_local_server(port=0)

            print("ZAPIS TOKENUW")
            # zapis tokenów lokalnie
            self.save_token(creds.id_token, creds.token)

            payload = jwt.decode(creds.id_token, options={"verify_signature": False})
            email = payload.get("email")
            print(f"user email {email}")
            # --- krok 2: wyślij id_token do FastAPI ---
            response = requests.get(
                f"http://localhost:8000/get_user/{email}"
            )

            if response.status_code == 200:
                data = response.json()
                self.LAST_ORDERS = data["last_orders"]
                print(self.LAST_ORDERS)
                # przejście na dashboard
                self.root.current = "dashboard"
                self.show_last_orders()
            else:
                print("Błąd backendu:", response.text)

        except Exception as e:
            print("Błąd Google login:", e)

        


     # --- toggle ulubionych ---
    def add_to_cart(self, pos):
        # Dodajemy id pozycji do koszyka
        self.CART.append(pos)
        self.update_cart_badge()
        screen = self.root.get_screen("position")
        cart_btn = screen.ids.add_to
        cart_btn.text = f"Dodaj do koszyka ({len(self.CART)})"
        print(f"Pozycja {pos} dodana do koszyka. Aktualny koszyk:", self.CART)

    # --- toggle ulubionych ---
    def toggle_favorite(self):

        pos = self.current_position
        pos["is_favorite"] = not pos.get("is_favorite", False)

        # aktualizacja ikony serduszka
        screen = self.root.get_screen("position")
        fav_btn = screen.ids.fav_btn
        fav_btn.icon = "heart" if pos["is_favorite"] else "heart-outline"

    def update_cart_badge(self):
        cart_count = len(self.CART)
        label = self.root.get_screen("dashboard").ids.cart_count
        label.text = str(cart_count) if cart_count > 0 else ""

    def show_last_orders(self):
        screen = self.root.get_screen("dashboard")
        box_last_orders = screen.ids.last_orders_box
        box_last_orders.clear_widgets()

        if not self.LAST_ORDERS:
            return

        for pos in self.LAST_ORDERS:
            print("pos", pos)
            pos = pos.get('menupositions')
            print("pos", pos)
            tile = PositionTile(
                orientation="vertical",
                size_hint_y=None,
                height=dp(300),
                size_hint_x=None,
                width=dp(235)
            )
            tile.bind(on_release=lambda inst, p=pos: self.open_position(p))
            # obrazek jako tło kafelka
            img = AsyncImage(
                source=pos.get("photo_url", ""),
                allow_stretch=True,
                keep_ratio=True,
                size_hint=(1, 1),
                pos_hint={"x": 0, "y": 0}
            )
            tile.add_widget(img)

                   # --- Overlay z napisami ---
            caption = BoxLayout(
                orientation="vertical",
                size_hint=(1, None),
                height=dp(60),
                pos_hint={"x": 0, "y": 0},   # na dole
                padding=[dp(5), dp(2)]
            )

            title = Label(
                text=pos.get("name", ""),
                color=(0, 0, 0, 1),
                font_size=dp(16),
                halign="left",
                valign="middle"
            )
            title.bind(size=lambda inst, val: setattr(inst, "text_size", val))

            desc = Label(
                text=pos.get("description", ""),
                color=(0, 0, 0, 1),
                font_size=dp(12),
                halign="left",
                valign="top"
            )
            desc.bind(size=lambda inst, val: setattr(inst, "text_size", val))

            caption.add_widget(title)
            caption.add_widget(desc)
            tile.add_widget(caption)

            box_last_orders.add_widget(tile)
    def open_cart(self):
        screen = self.root.get_screen("cart")
        box = screen.ids.cart_box
        box.clear_widgets()

        for item in self.CART:  # self.CART = lista dictów np. {"name":..., "qty":..., "price":...}
            row = MDBoxLayout(orientation="horizontal", size_hint_y=None, height=dp(40), spacing=dp(10))

            # nazwa produktu
            row.add_widget(MDLabel(text=item["name"], halign="left"))

            # pole edycji ilości
            qty_field = MDTextField(
                text=str(item["qty"]),
                input_filter="int",
                size_hint_x=None,
                width=dp(60)
            )
            row.add_widget(qty_field)

            # cena
            row.add_widget(MDLabel(text=f'{item["price"]} zł', halign="right"))

            box.add_widget(row)

        self.root.current = "cart"

    def confirm_order(self):
        screen = self.root.get_screen("cart")
        notes = screen.ids.notes_field.text

        # sprawdź wybraną metodę dostawy
        delivery = "local"
        for rb in screen.ids.values():
            if hasattr(rb, "group") and rb.group == "delivery" and rb.active:
                delivery = rb.value

        print("Potwierdzam zamówienie:", self.CART, notes, delivery)
        
        # tutaj możesz wysłać POST do backendu
    def show_positions(self, positions):
        screen = self.root.get_screen("dashboard")
        box_popular = screen.ids.popular_box
        box_fav = screen.ids.favorites_box
        box_popular.clear_widgets()
        box_fav.clear_widgets()

        for pos in positions:
            tile = PositionTile(
                orientation="vertical",
                size_hint_y=None,
                height=dp(300),
                size_hint_x=None,
                width=dp(235)
            )

            # obrazek jako tło kafelka
            img = AsyncImage(
                source=pos.get("photo_url", ""),
                allow_stretch=True,
                keep_ratio=True,
                size_hint=(1, 1),
                pos_hint={"x": 0, "y": 0}
            )
            tile.add_widget(img)

                   # --- Overlay z napisami ---
            caption = BoxLayout(
                orientation="vertical",
                size_hint=(1, None),
                height=dp(60),
                pos_hint={"x": 0, "y": 0},   # na dole
                padding=[dp(5), dp(2)]
            )

            title = Label(
                text=pos.get("name", ""),
                color=(0, 0, 0, 1),
                font_size=dp(16),
                halign="left",
                valign="middle"
            )
            title.bind(size=lambda inst, val: setattr(inst, "text_size", val))

            desc = Label(
                text=pos.get("description", ""),
                color=(0, 0, 0, 1),
                font_size=dp(12),
                halign="left",
                valign="top"
            )
            desc.bind(size=lambda inst, val: setattr(inst, "text_size", val))

            caption.add_widget(title)
            caption.add_widget(desc)
            tile.add_widget(caption)

            # kliknięcie kafelka → otwarcie ekranu pozycji
            tile.bind(on_release=lambda inst, p=pos: self.open_position(p))

            if pos.get("is_favorite"):
                box_fav.add_widget(tile)
            else:
                box_popular.add_widget(tile)

    def show_dashboard(self, popular, favorites):
        # zamiast wywoływać show_positions bez argumentu
        self.show_positions(popular + favorites)

    def save_address(self):
        delivery_screen = self.root.get_screen("delivery")
        data = {
            "street": delivery_screen.ids.street.text,
            "city": delivery_screen.ids.city.text,
            "postal": delivery_screen.ids.postal.text,
            "phone": delivery_screen.ids.phone.text,
        }
        try:
            response = requests.post("http://127.0.0.1:8000/user/address", json=data)
            if response.status_code == 200:
                print("Adres zapisany:", response.json())
            else:
                print("Błąd zapisu:", response.text)
        except Exception as e:
            print("Błąd sieci:", e)

    def handle_pickup(self):
        print("Wybrano odbiór osobisty")

    def handle_quick_pickup(self):
        print("Wybrano odbiór osobisty quick")

    def open_profile_menu(self, caller):
        menu_items = [
            {
                "text": "Wyloguj",
                "viewclass": "OneLineListItem",
                "on_release": lambda x=None: self.logout()
            }
        ]
        self.profile_menu = MDDropdownMenu(
            caller=caller,
            items=menu_items,
            width_mult=3,
            ver_growth="up"   # <-- menu otwiera się w górę
        )
        self.profile_menu.open()

    def logout(self):
        # ścieżka do pliku loginLog.json
        file_path = os.path.join(os.getcwd(), "loginLog.json")

        # sprawdź i usuń
        if os.path.exists(file_path):
            os.remove(file_path)
            print("Plik loginlog.json został usunięty")
        else:
            print("Plik loginlog.json nie istnieje")

        # przejście na ekran logowania
        self.root.current = "login"

    def open_search(self):
        print("Otwieram szukajkę")
        # tu możesz otworzyć nowy ekran z polem wyszukiwania

    def open_menu(self):
        print("Otwieram menu")
        # tu możesz przejść na ekran menu
    
    def open_profile(self):
        print("Otwieram profil")
        # tu możesz przejść na ekran menu

    def save_login_data(self, data: dict):
        # wybierz odpowiednią ścieżkę w zależności od platformy
        if platform == "android":
            # na Androidzie najlepiej użyć katalogu aplikacji
            from android.storage import app_storage_path
            path = app_storage_path()
        elif platform == "ios":
            # na iOS można użyć katalogu dokumentów
            from plyer import storagepath
            path = storagepath.get_documents_dir()
        else:
            # fallback np. na desktop
            path = os.getcwd()

        file_path = os.path.join(path, "loginLog.json")

        # zapisz dane do pliku JSON
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=4)

        print(f"Zapisano loginLog.json w: {file_path}")

    def check_user_exists(self, fingerprint: str) -> bool:
        """
        Wywołanie FastAPI: sprawdza czy użytkownik istnieje w bazie.
        """
        try:
            resp = httpx.get("https://api.example.com/check_user",
                             params={"fingerprint": fingerprint})
            data = resp.json()
            return data.get("exists", False)
        except Exception as e:
            print("Błąd sprawdzania użytkownika:", e)
            return False

    # --- Rejestracja ---
    def register(self):
        email = self.root.get_screen("register").ids.email.text
        phone = self.root.get_screen("register").ids.phone.text
        password = self.root.get_screen("register").ids.password.text
        encoded_pwd = base64.b64encode(password.encode("utf-8")).decode("utf-8")
        resp = httpx.post("http://127.0.0.1:8000/register",
                          data={"email": email, "telephone_number": phone, "password": encoded_pwd, "address": "defaultaddress"},
                          headers={"Content-Type": "application/x-www-form-urlencoded"})
        
        if resp.json().get("password") is None:
            raise BaseException("Rejestracja nieudana")
        
        print("Rejestracja:", resp.json())
        self.switch_to_login()
        


    

    def set_address(self, user_id, street_and_number: str, city: str, postal_code: str):
        street = self.root.get_screen("delivery").ids.street.text
        city = self.root.get_screen("delivery").ids.city.text
        postal = self.root.get_screen("delivery").ids.postal.text
        phone = self.root.get_screen("delivery").ids.phone.text
    def login(self):
        email = self.root.get_screen("login").ids.email.text
        password = self.root.get_screen("login").ids.password.text
        encoded_pwd = base64.b64encode(password.encode("utf-8")).decode("utf-8")

        try:
            resp = httpx.post("http://127.0.0.1:8000/login",
            data={"email": email, "password": encoded_pwd},   # UWAGA: data zamiast json
            headers={"Content-Type": "application/x-www-form-urlencoded"}
            )

            if resp.status_code == 200:
                # upewnij się, że odpowiedź ma treść
                if resp.text.strip():
                    resp_json = resp.json()
                    # obsłuż poprawny login
                    print("Login OK:", resp_json)
                    resp_json = resp.json()

                    if resp_json.get("jwt") is None:
                        raise BaseException("Logowanie nieudane")
                    
                    self.save_login_data(resp_json)
                    self.switch_to_dashboard()
                else:
                    print("Login OK, ale brak treści w odpowiedzi")
            else:
                print("Błąd logowania:", resp.status_code, resp.text)

        except Exception as e:
            print("Wyjątek podczas logowania:", e)


    def load_and_decode_jwt():
        file_path = os.path.join(os.getcwd(), "loginlog.json")

        if not os.path.exists(file_path):
            print("Plik loginlog.json nie istnieje")
            return None

        # odczyt pliku
        with open(file_path, "r") as f:
            data = json.load(f)

        token = data.get("jwt")
        if not token:
            print("Brak JWT w pliku")
            return None

        try:
            # dekodowanie JWT (bez weryfikacji podpisu)
            decoded = jwt.decode(token, options={"verify_signature": False})
            print("Dekodowany JWT:", decoded)
            return decoded
        except Exception as e:
            print("Błąd dekodowania JWT:", e)
            return None    
        
    # --- Nawigacja ---
    def switch_to_login(self):
        self.root.current = "login"

    def switch_to_register(self):
        self.root.current = "register"
    def switch_to_dashboard(self):
        self.root.current = "dashboard"
        self.on_start()


if __name__ == "__main__":
    FastFoodApp().run()