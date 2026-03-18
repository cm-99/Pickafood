# Image-based estimation of meal caloric and nutritional value

This project consists of a server application and a mobile app (iOS 18.5+), which together form a system that allows users to estimate the nutritional value of meals from photos and manage the collected data on their phone.

![alt text](https://github.com/cm-99/Pickafood/blob/main/analiza_posilku.jpg)
![alt text](https://github.com/cm-99/Pickafood/blob/main/historia_posilkow.jpg)

Program porównano z rozwiązaniami o podobnej funkcjonalności wykorzystując zbiór 7 posiłków złożonych (od 2 do 5 składników). Wyniki w postaci średnich bezwzględnych wartości błędów procentowych dla szacowanych wartości odżywczych:

| Aplikacja | Kalorie | Białko | Węglowodany | Tłuszcz |
| ------------- | :-------------: |:-------------: |:-------------: |:-------------: |
| Pickafood  | 24,88% | 26,17% | 59,25% | 38,32% |
| CalAI | 33,68% | 69,31% | 15,4% | 68,96% |
| FatSecret | 23,36% | 40,32% | 35,51% | 62,74% |
| MyFitnessPal | 27,80% | 47,19% | 26,40% | 68,65% |

----------------------------------------------------------------------------------------------

# Szacowanie kaloryczności i wartości odżywczych posiłków na podstawie zdjęcia

Zamieszczony projekt składa się z aplikacji serwera oraz mobilnej (iOS 18.5+), które w połączeniu tworzą system umożliwiający estymację wartości odżywczych posiłków ze zdjęć oraz zarządzanie zebranymi danymi na telefonie.

![alt text](https://github.com/cm-99/Pickafood/blob/main/analiza_posilku.jpg)
![alt text](https://github.com/cm-99/Pickafood/blob/main/historia_posilkow.jpg)

The program was compared with solutions offering similar functionality using a set of 7 complex meals (2 to 5 ingredients). Results are presented as mean absolute percentage error values for the estimated nutritional values:

| App | Calories | Protein | Carbohydrates | Fat |
| ------------- | :-------------: |:-------------: |:-------------: |:-------------: |
| Pickafood  | 24,88% | 26,17% | 59,25% | 38,32% |
| CalAI | 33,68% | 69,31% | 15,4% | 68,96% |
| FatSecret | 23,36% | 40,32% | 35,51% | 62,74% |
| MyFitnessPal | 27,80% | 47,19% | 26,40% | 68,65% |
