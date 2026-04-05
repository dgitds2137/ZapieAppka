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

from kivy.properties import StringProperty, NumericProperty
from kivymd.uix.screen import MDScreen
from kivymd.uix.card import MDCard
import requests

API = "http://127.0.0.1:8000"
from kivy.metrics import sp


from kivy.uix.behaviors import ButtonBehavior
from kivy.uix.boxlayout import BoxLayout

class ProductCard(ButtonBehavior, BoxLayout):
    title = StringProperty("")
    desc = StringProperty("")
    image = StringProperty("")
    calories = StringProperty("")
    prep_time = StringProperty("15 min")
    position_id = NumericProperty(0)


class DashboardScreen(MDScreen):
    def on_pre_enter(self, *args):
        self.ids.popular_label.font_size = sp(48)
        self.load_products()

    def load_products(self):
        try:
            resp = httpx.get("http://127.0.0.1:8000/positions", timeout=8)
            if resp.status_code == 200:
                products = resp.json()
                self.show_products(products[:8])
            else:
                print("Błąd pobierania pozycji:", resp.status_code, resp.text)
        except Exception as e:
            print("Błąd ładowania produktów:", e)

    def show_products(self, products):
        box = self.ids.popular_box
        box.clear_widgets()

        for p in products:
            card = ProductCard(
                title=str(p.get("name", "")),
                desc=str(p.get("description", "")),
                image=str(p.get("photo_url", "")),
                calories=f"kcal: {p.get('calories', 0)}" if p.get("calories") is not None else "",
                prep_time="15 min",
                position_id=int(p.get("position_id", 0) or 0),
            )
            card.bind(on_release=lambda inst, pos=p: App.get_running_app().open_position(pos))
            box.add_widget(card)

    def open_product(self, pos):
        app = App.get_running_app()
        if hasattr(app, "open_position"):
            app.open_position(pos)
        else:
            print("Kliknięto produkt:", pos.get("name"))

    def show_popular_products(self, products):
        box = self.ids.popular_box
        box.clear_widgets()

        for p in products:
            card = ProductCard(
                title=str(p.get("name", "")),
                desc=str(p.get("description", "")),
                image=str(p.get("photo_url", "")),
                calories=f"kcal: {p.get('calories', 0)}" if p.get("calories") is not None else "",
                prep_time="15 min",
                position_id=int(p.get("position_id", 0) or 0),
            )
            card.bind(on_release=lambda inst, pos=p: self.open_product(pos))
            box.add_widget(card)

    def open_product(self, pos):
        app = self.manager.app if hasattr(self.manager, "app") else None
        if app and hasattr(app, "open_position"):
            app.open_position(pos)
        else:
            print("Kliknięto produkt:", pos.get("name"))

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


    def on_start(self):
        try:
            response = requests.get("http://127.0.0.1:8000/positions")
            if response.status_code == 200:
                positions = response.json()
                screen = self.root.get_screen("dashboard")
                screen.show_products(positions)
            else:
                print("Błąd pobierania pozycji:", response.text)
        except Exception as e:
            print("Błąd sieci:", e)


    def build(self):
        token = self.load_token()
        print("token", token)
        self.theme_cls.font_styles["H1"] = ["Poppins", 32, False, 0.15]
        if token:
            self.root.current = "dashboard"
        else:
            self.root.current = "login"

        print("BUILD")
        return super().build()


    def go_back(self):
        # wraca do dashboard albo innego ekranu
        self.root.current = "dashboard"
        
    def set_delivery(self, method):
        if method == "local":
            self.delivery_method = "local"
        else:
            self.delivery_method = "delivery"
        print("Wybrana metoda dostawy:", self.delivery_method)


    def load_addresses(self):
        r = requests.get(f"{API}/addresses")
        if r.status_code == 200:
            return r.json()
        return []

    def set_selected_address(self, address_id):
        self.selected_address = address_id

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


    def reorder(self, order_id):
        r = requests.post(f"{API}/orders/{order_id}/reorder")
        if r.status_code == 200:
            return r.json()
        print("Błąd reorder:", r.text)
        return None

    def add_to_cart(self, pos_id: int):
        self.cart[pos_id] = self.cart.get(pos_id, 0) + 1

    def change_cart_qty(self, pos_id: int, delta: int):
        if pos_id not in self.cart:
            return
        self.cart[pos_id] += delta
        if self.cart[pos_id] <= 0:
            del self.cart[pos_id]

    def go_back(self):
        self.root.current = "dashboard"

    def go_to(self, screen_name):
        self.root.current = screen_name


    def show_positions(self, positions):
        # tutaj wstawiasz logikę do dashboardu
        # np. wypełnianie MDList
        pass
    

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
        self.current_position = pos
        screen = self.root.get_screen("position")
        screen.pos_id = pos["position_id"]
        screen.pos_data = pos

        if "pos_image" in screen.ids:
            screen.ids.pos_image.source = pos.get("photo_url", "")
        if "pos_title" in screen.ids:
            screen.ids.pos_title.text = pos.get("name", "")
        if "pos_desc" in screen.ids:
            screen.ids.pos_desc.text = pos.get("description", "")

        self.root.current = "position"

    def get_storage_path(self):
        if platform == "android":
            from android.storage import app_storage_path
            return app_storage_path()
        elif platform == "ios":
            from plyer import storagepath
            return storagepath.get_documents_dir()
        else:
            return os.getcwd()
    

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
            else:
                print("Błąd backendu:", response.text)

        except Exception as e:
            print("Błąd Google login:", e)

        


     # --- toggle ulubionych ---
    def add_to_cart(self, pos):
        # Dodajemy id pozycji do koszyka
        self.CART.append(pos)
        screen = self.root.get_screen("position")
        cart_btn = screen.ids.add_to
        cart_btn.text = f"Dodaj do koszyka ({len(self.CART)})"
        print(f"Pozycja {pos} dodana do koszyka. Aktualny koszyk:", self.CART)

    def toggle_favorite(self):

        pos = self.current_position
        pos["is_favorite"] = not pos.get("is_favorite", False)

        # aktualizacja ikony serduszka
        screen = self.root.get_screen("position")
        fav_btn = screen.ids.fav_btn
        fav_btn.icon = "heart" if pos["is_favorite"] else "heart-outline"

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